# typed: true
# frozen_string_literal: true

module AutoHCK
  class HCKTest
    # Coordinate Secure Boot popups with verified EFI boot evidence.
    class SecureBootManualController
      DIRECTORY = 'C:\\AutoHCK\\SecureBootManual'
      REQUEST_PATH = "#{DIRECTORY}\\request.json".freeze
      ACK_PATH = "#{DIRECTORY}\\ack.json".freeze
      REQUEST_ID_PATTERN = /\A[a-zA-Z0-9_-]{1,80}\z/
      BOOT_EVENTS = %w[REQUEST_UFD1 REQUEST_UFD2 CHANGE_UFD2_TO_MSFT_TEST].freeze
      QUESTIONS = {
        'RESULT_UFD1' => [1, 'pressanykey1', 'UFD #1 Boot Result',
                          'Did UFD #1 boot and display "** 1 ** pressanykey1.efi"?'],
        'RESULT_UFD2' => [2, 'pressanykey2', 'UFD #2 Boot Result',
                          'Did UFD #2 boot and display "** 2 ** pressanykey2.efi"?'],
        'RESULT_MSFT' => [2, 'msft_test_pressanykey', 'UFD Test App Boot Result',
                          'Did UFD boot and display "** TEST ** msft_test_pressanykey.efi"?']
      }.freeze

      def initialize(project:, tools:, client_name:, client_id:, logger:)
        @project = project
        @tools = tools
        @client_name = client_name
        @client_id = format('%02d', client_id)
        @logger = logger
        configure_artifact_paths(project)
        @lock = Mutex.new
        @responses = {}
        @round = nil
        @consumed = false
        @ufd2_app = 'pressanykey2'
        @regular_usb_bootindex = nil
        @stopped = false
        @last_issue = nil
      end

      def configure_artifact_paths(project)
        prefix = format('%<run>04d_%<client>s', run: project.id.to_i, client: @client_id)
        @serial_path = File.join(project.workspace_path, "uefi_serial_#{prefix}.log")
        @audit_path = File.join(project.workspace_path, "secure_boot_rounds_#{prefix}.jsonl")
      end

      # Observe firmware while Windows handles popups and reboots.
      def start
        @worker = Thread.new do
          until @stopped
            @lock.synchronize { observe_round }
            sleep 0.25
          end
        rescue StandardError => e
          @lock.synchronize do
            @worker_failed = "Serial worker stopped: #{e.class}: #{e.message}"
            @round&.invalidate(@worker_failed)
          end
          @logger.error("Secure Boot: #{@worker_failed}; no further acknowledgements")
        end
        @logger.info("Secure Boot serial monitor started: #{@serial_path}; audit: #{@audit_path}")
        self
      end

      # Stop observation and restore normal USB boot priority.
      def close
        @stopped = true
        if @worker && !@worker.join(15)
          @logger.error('Secure Boot serial monitor did not stop; terminating worker, leaving results unanswered')
          @worker.kill.join
        end
        @lock.synchronize do
          next unless @round && current_session.equal?(@round.session)

          restore_bootindex
          restore_regular_usb_bootindex
        end
      rescue StandardError => e
        @logger.error("Secure Boot monitor cleanup: #{e.message}")
      ensure
        @logger.info('Secure Boot serial monitor stopped')
      end

      # Acknowledge guest popups only when their action or result is ready.
      def poll
        request = pending_request
        return unless request

        payload = @lock.synchronize { response_for(request) }
        return unless payload

        write_ack(payload)
        mark_acknowledged(request)
      rescue Tools::ToolsHCKError => e
        # A guest reboot delays acknowledgement until WinRM returns.
        @logger.debug("Secure Boot manual test: #{@client_name} WinRM unavailable: #{e.message}")
      rescue StandardError => e
        report_poll_error(e)
      end

      def pending_request
        raw = read_request
        return if raw.empty?

        request = JSON.parse(raw.delete_prefix("\uFEFF"))
        id = request.fetch('id')
        event = request.fetch('event')
        raise ArgumentError, 'Invalid request id' unless id.is_a?(String) && id.match?(REQUEST_ID_PATTERN)
        unless BOOT_EVENTS.include?(event) || QUESTIONS.key?(event)
          raise ArgumentError, "Unknown Secure Boot request: #{event.inspect}"
        end

        request
      end

      def mark_acknowledged(request)
        id = request.fetch('id')
        event = request.fetch('event')
        @lock.synchronize do
          @consumed = true if QUESTIONS.key?(event)
          @responses.fetch(id)[:delivered] = true
        end
        @last_issue = nil
        @logger.info("Secure Boot manual test: acknowledged #{event} (#{id}) on #{@client_name}")
      end

      def report_poll_error(error)
        issue = "#{error.class}: #{error.message}"
        return if issue == @last_issue

        @last_issue = issue
        @logger.error("Secure Boot manual test: no popup acknowledgement: #{issue}")
      end

      private

      private :configure_artifact_paths, :pending_request, :mark_acknowledged, :report_poll_error

      def current_session
        @project.setup_manager.hypervisor_client_session(@client_name)
      end

      # Preserve evidence for automatic popup answers.
      def audit(action, **details)
        record = { time: Time.now.utc.iso8601, action: action, round_id: @round&.id }.merge(details)
        message = JSON.generate(record)
        File.open(@audit_path, 'a') { |file| file.puts(message) }
        @logger.info("Secure Boot: #{message}")
        true
      rescue StandardError => e
        # Leave results unanswered if their evidence cannot be saved.
        @audit_failed ||= "Secure Boot audit failed: #{e.class}: #{e.message}"
        @round&.invalidate(@audit_failed)
        @logger.error("#{@audit_failed}; leaving results unanswered")
        false
      end

      # Keep each popup tied to one stable reply across retries.
      def response_for(request)
        raise EngineError, @worker_failed if @worker_failed
        raise EngineError, @audit_failed if @audit_failed

        id = request.fetch('id')
        if (cached = @responses[id])
          return cached_response_for(request, cached)
        end

        payload = new_response_for(request)
        @responses[id] = { request: request, payload: payload, delivered: false }
        payload
      end

      def cached_response_for(request, cached)
        raise ArgumentError, 'Request ID reused with different contents' unless cached[:request] == request
        return if cached[:delivered]

        observe_round
        raise EngineError, @round.reason if @round.state == :uncertain

        cached[:payload]
      end

      def new_response_for(request)
        event = request.fetch('event')
        id = request.fetch('id')
        payload = { 'id' => id, 'event' => event, 'status' => 'READY' }
        if BOOT_EVENTS.include?(event)
          arm_round(request)
        else
          payload.merge!(result_for(request))
        end
        payload
      end

      # Prepare the requested USB boot before the watcher continues.
      def arm_round(request)
        ensure_previous_round_available(request)
        @round = build_round(request)
        reset_round_state(request.fetch('event'))
        audit_armed_round
        select_ufd(@round.ufd)
        @round.observe(current_session)
        raise EngineError, @round.reason if @round.state == :uncertain
      rescue StandardError => e
        @round&.invalidate("Cannot arm boot: #{e.message}")
        raise
      end

      def ensure_previous_round_available(request)
        observe_round if @round && !@consumed
        return unless @round && !@consumed && !insertion_after_change?(request)

        raise EngineError, "Previous round #{@round.id} has no acknowledged result; refusing another boot"
      end

      # Accept an extra UFD #2 insertion popup before replacement boot begins.
      def insertion_after_change?(request)
        @armed_by_change && request['event'] == 'REQUEST_UFD2' && @round&.state == :armed
      end

      def build_round(request)
        event = request.fetch('event')
        ufd = event == 'REQUEST_UFD1' ? 1 : 2
        @ufd2_app = 'msft_test_pressanykey' if event == 'CHANGE_UFD2_TO_MSFT_TEST'
        session = current_session
        raise EngineError, 'QEMU session not available' unless session

        SecureBootSerialRound.new(id: request.fetch('id'), ufd: ufd,
                                  app: ufd == 1 ? 'pressanykey1' : @ufd2_app,
                                  path: @serial_path, session: session)
      end

      def reset_round_state(event)
        @consumed = false
        @restored = false
        @reported_failure = false
        @armed_by_change = event == 'CHANGE_UFD2_TO_MSFT_TEST'
      end

      def audit_armed_round
        details = { ufd: @round.ufd, app: @round.app, offset: @round.offset, session: @round.session.object_id }
        return if audit('armed', **details)

        raise EngineError, @audit_failed
      end

      # Respond to confirmed EFI prompts and boot outcomes.
      def observe_round
        return unless @round && !@consumed

        previous_state = @round.state
        @round.observe(current_session)
        if @round.state == :waiting
          respond_to_waiting_round
        elsif @round.complete? && !@restored
          restore_bootindex
        end
        audit_completed_round(previous_state)
        report_uncertain
      rescue StandardError => e
        @round.invalidate("Firmware action failed: #{e.class}: #{e.message}")
        report_uncertain
      end

      def respond_to_waiting_round
        restore_bootindex
        # Confirm the EFI prompt remains active before sending a key.
        @round.observe(current_session)
        raise EngineError, 'EFI wait state changed before key injection' unless @round.state == :waiting

        @round.key_sent!
        return unless audit('sending_key', app: @round.app, evidence: @round.evidence)

        qmp('send-key', { 'keys' => [{ 'type' => 'qcode', 'data' => 'ret' }], 'hold-time' => 100 })
      end

      def audit_completed_round(previous_state)
        return unless @round.complete? && @round.state != previous_state

        audit('observed', outcome: @round.state, evidence: @round.evidence)
      end

      # Leave unreliable results unanswered for manual review.
      def report_uncertain
        return unless @round.state == :uncertain && !@reported_failure

        @reported_failure = true
        audit('uncertain', reason: @round.reason, evidence: @round.evidence)
        @logger.error("Secure Boot round #{@round.id}: #{@round.reason}; " \
                      'leaving result unanswered, no key will be sent')
      end

      # Answer a popup only from matching, complete boot evidence.
      def result_for(request)
        question = validate_result_request(request)
        answer = confirmed_result_answer
        audit_answer(request, question, answer)
        { 'round_id' => @round.id, 'question' => question, 'answer' => answer }
      end

      def validate_result_request(request)
        raise EngineError, 'Result without a current boot round' unless @round
        raise EngineError, 'Round ID missing or stale' unless request['round_id'] == @round.id
        raise EngineError, 'This round already has an acknowledged result' if @consumed

        ufd, app, title, question = QUESTIONS.fetch(request.fetch('event'))
        validate_result_identity(request, ufd, app, title, question)

        question
      end

      def validate_result_identity(request, ufd, app, title, question)
        return if request['title'] == title && request['question'] == question && @round.ufd == ufd && @round.app == app

        raise EngineError, 'Result popup question/title/application does not match this boot round'
      end

      def confirmed_result_answer
        observe_round
        unless @round.complete? && @restored
          raise EngineError, "No reliable result for #{@round.id}: #{@round.reason || @round.state}"
        end

        @round.state == :allowed ? 'Yes' : 'No'
      end

      def audit_answer(request, question, answer)
        return if audit('answer', request_id: request.fetch('id'), question: question,
                                  answer: answer, evidence: @round.evidence)

        raise EngineError, @audit_failed
      end

      def read_request
        command = "if (Test-Path -LiteralPath '#{REQUEST_PATH}') { Get-Content -LiteralPath '#{REQUEST_PATH}' -Raw }"
        result = @tools.act_with_tools_on_machine(@client_name) do |tools|
          tools.run_on_machine(@client_name, command)
        end
        return '' if result == true

        result.to_s.strip
      end

      def device_path(number)
        "/machine/peripheral/svvp_ufd#{number}_#{@client_id}"
      end

      def regular_usb_path
        "/machine/peripheral/hlk_usb_stick_#{@client_id}"
      end

      # Keep firmware actions tied to the round's QEMU session.
      def qmp(execute, arguments)
        Timeout.timeout(10) do
          @project.setup_manager.run_hypervisor_client_command(
            @client_name, execute, arguments, session: @round.session
          )
        end
      end

      def set_bootindex(number, value)
        qmp('qom-set', { 'path' => device_path(number), 'property' => 'bootindex', 'value' => value })
      end

      def verify_bootindex(number, expected)
        actual = qmp('qom-get', { 'path' => device_path(number), 'property' => 'bootindex' })
        return if actual == expected

        raise EngineError, "UFD #{number} bootindex is #{actual.inspect}, expected #{expected}"
      end

      # Give the requested USB drive priority for the next boot.
      def select_ufd(active)
        inactive = active == 1 ? 2 : 1
        set_bootindex(inactive, -1)
        demote_regular_usb
        set_bootindex(active, 0)
        verify_bootindex(inactive, -1)
        verify_bootindex(active, 0)
      end

      # Keep the general USB stick out of the manual test's boot attempts.
      def demote_regular_usb
        return unless @regular_usb_bootindex.nil?

        index = qmp('qom-get', { 'path' => regular_usb_path, 'property' => 'bootindex' })
        unless index.is_a?(Integer) && index.zero?
          raise EngineError, "General USB stick bootindex is #{index.inspect}, expected 0"
        end

        @regular_usb_bootindex = index
        qmp('qom-set', { 'path' => regular_usb_path, 'property' => 'bootindex', 'value' => -1 })
        verify_regular_usb_bootindex(-1)
      end

      def restore_regular_usb_bootindex
        return if @regular_usb_bootindex.nil?

        qmp('qom-set', { 'path' => regular_usb_path, 'property' => 'bootindex', 'value' => @regular_usb_bootindex })
        verify_regular_usb_bootindex(@regular_usb_bootindex)
        @regular_usb_bootindex = nil
      end

      def verify_regular_usb_bootindex(expected)
        actual = qmp('qom-get', { 'path' => regular_usb_path, 'property' => 'bootindex' })
        return if actual == expected

        raise EngineError, "General USB stick bootindex is #{actual.inspect}, expected #{expected}"
      end

      # Restore normal boot priority after the USB attempt.
      def restore_bootindex
        reset_bootindexes
        verify_reset_bootindexes
        @restored = true
        audit('bootindex_restored')
      end

      def reset_bootindexes
        [1, 2].each { |number| set_bootindex(number, -1) }
      end

      def verify_reset_bootindexes
        [1, 2].each { |number| verify_bootindex(number, -1) }
      end

      # Return the approved action or answer to the guest watcher.
      def write_ack(response)
        payload = JSON.generate(response).gsub("'", "''")
        command = "New-Item -ItemType Directory -Path '#{DIRECTORY}' -Force | Out-Null; " \
                  "Set-Content -LiteralPath '#{ACK_PATH}.tmp' -Value '#{payload}' -Encoding Ascii -NoNewline; " \
                  "Move-Item -LiteralPath '#{ACK_PATH}.tmp' -Destination '#{ACK_PATH}' -Force"
        @tools.act_with_tools_on_machine(@client_name) do |tools|
          tools.run_on_machine(@client_name, command)
        end
      end
    end
  end
end
