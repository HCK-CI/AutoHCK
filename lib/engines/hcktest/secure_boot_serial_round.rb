# frozen_string_literal: true

module AutoHCK
  class HCKTest
    # Observe one requested USB boot using new output from the firmware serial log.
    # The caller polls this object and handles keyboard input.
    #
    # Allowed: the expected EFI app ran, a key attempt was recorded, and firmware
    # then started Windows Boot Manager.
    # Blocked: firmware explicitly denied the requested USB boot and then started
    # Windows Boot Manager.
    # Uncertain: the evidence is incomplete, unexpected, or unreliable.
    class SecureBootSerialRound
      class Uncertain < StandardError; end

      APPS = {
        'Welcome to the pressanykey1 efi app' => 'pressanykey1',
        'Welcome to the pressanykey2 efi app' => 'pressanykey2',
        '** 1 ** pressanykey1.efi' => 'pressanykey1',
        '** 2 ** pressanykey2.efi' => 'pressanykey2',
        '** TEST ** msft_test_pressanykey.efi' => 'msft_test_pressanykey',
        'Welcome to the pressanykey MSFT test-signed efi app' => 'msft_test_pressanykey'
      }.freeze
      WAIT_PROMPT = 'Press any key to continue...'
      MAX_READ = 1024 * 1024
      TIMEOUT = 600

      attr_reader :id, :ufd, :app, :session, :state, :reason, :offset, :evidence

      def initialize(boot:, path:, session:, boot_menu_recovery: false)
        @id = boot.fetch(:id)
        @ufd = boot.fetch(:ufd)
        @app = boot.fetch(:app)
        @path = path
        @session = session
        @boot_menu_recovery = boot_menu_recovery
        @state = :armed
        @pending = ''.b
        @evidence = []
        @started_at = monotonic_time
        File.open(@path, 'rb') do |file|
          @identity = identity(file.stat)
          @offset = file.size
          @anchor = anchor(file)
        end
      end

      # Mark the round uncertain if its firmware evidence cannot be trusted.
      def observe(session)
        return if @state == :uncertain

        raise Uncertain, 'QEMU session changed during this round' unless session.equal?(@session)
        raise Uncertain, 'Timed out waiting for complete EFI/Windows evidence' if monotonic_time - @started_at > TIMEOUT

        File.open(@path, 'rb') { |file| read_new(file) }
      rescue StandardError => e
        invalidate("#{e.class}: #{e.message}")
      end

      def invalidate(reason)
        return if @state == :uncertain

        @reason = reason
        @state = :uncertain
      end

      # Allow one key attempt only at the expected EFI prompt.
      def key_sent!
        raise Uncertain, 'Key injection outside the observed EFI wait prompt' unless @state == :waiting

        @state = :key_sent
      end

      # Record one attempt to return from the firmware boot menu to Windows.
      def menu_selection_sent!
        raise Uncertain, 'Boot menu selection without the expected choices' unless @state == :menu_ready

        @state = :menu_selection_sent
      end

      # A matching result popup proves Windows returned after the menu selection.
      def guest_result_confirmed!
        unless @boot_menu_recovery && @state == :menu_selection_sent
          raise Uncertain, 'Guest result without a verified firmware boot menu selection'
        end

        @state = :allowed
      end

      def complete?
        %i[allowed blocked].include?(@state)
      end

      private

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def identity(stat)
        [stat.dev, stat.ino]
      end

      def anchor(file)
        size = [@offset, 256].min
        file.seek(@offset - size)
        file.read(size)
      end

      # Read reliable new firmware output for this boot attempt.
      def read_new(file)
        verify_serial_log(file)
        file.seek(@offset)
        bytes = file.read(MAX_READ + 1) || ''.b
        raise Uncertain, 'Serial backlog exceeded the per-poll limit' if bytes.bytesize > MAX_READ

        @offset += bytes.bytesize
        @anchor = anchor(file)
        @pending << bytes
        consume_lines
        raise Uncertain, 'Unterminated serial line exceeded the limit' if @pending.bytesize > MAX_READ
      end

      def verify_serial_log(file)
        return if identity(file.stat) == @identity && file.size >= @offset && anchor(file) == @anchor

        raise Uncertain, 'Serial log replaced, truncated, or rewritten (including truncate-and-regrow)'
      end

      # Normalize firmware text before checking expected messages.
      def clean(line)
        line.gsub(%r{\e\[[0-?]*[ -/]*[@-~]}, '').strip
      end

      # Process complete firmware messages while preserving unfinished output.
      def consume_lines
        while (ending = @pending.index(/[\r\n]/))
          line = @pending.slice!(0, ending + 1)
          @state == :boot_menu ? consume_boot_menu(line) : consume(clean(line))
        end
        if @state == :boot_menu && @pending.include?('ENTER to select boot device')
          consume_boot_menu(@pending)
          @pending.clear
        end
        # Recognize the EFI app's input prompt promptly.
        return unless clean(@pending) == WAIT_PROMPT

        consume(WAIT_PROMPT)
        @pending.clear
      end

      # Classify expected firmware messages for the active boot attempt.
      def consume(line)
        return if line.empty?

        match = usb_boot_match(line)
        return usb_line(line, match[1].to_i) if match
        return application_line(line) if APPS.key?(line)
        return wait_prompt_line(line) if line == WAIT_PROMPT

        consume_boot_status(line)
      end

      def consume_boot_status(line)
        if line.match?(/\ABdsDxe: starting .*"BootManagerMenuApp"/)
          boot_menu_line(line)
        elsif line.match?(/\ABdsDxe: starting .*"Windows Boot Manager"/)
          windows_line(line)
        elsif @state == :boot_menu
          consume_boot_menu(line)
        elsif line.start_with?('Welcome to the pressanykey')
          raise Uncertain, "Unrecognized EFI application: #{line}"
        end
      end

      def boot_menu_line(line)
        unless @boot_menu_recovery && @state == :key_sent
          raise Uncertain, 'Unexpected firmware boot menu after the EFI application'
        end

        @evidence << line
        @menu_output = ''.b
        @state = :boot_menu
      end

      # Require the observed menu to offer the requested UFD first and Windows second.
      def consume_boot_menu(line)
        @menu_output << line << "\n"
        raise Uncertain, 'Firmware boot menu output exceeded the limit' if @menu_output.bytesize > MAX_READ
        return unless @menu_output.include?('ENTER to select boot device')

        choices = boot_menu_choices
        expected = "SVVPUFD#{@ufd}"
        unless choices[0]&.end_with?(expected) && choices[1] == 'Windows Boot Manager'
          raise Uncertain, "Unexpected firmware boot menu choices: #{choices.inspect}"
        end

        @evidence << "Boot menu: #{choices.first(2).join(', ')}"
        @state = :menu_ready
      end

      def boot_menu_choices
        header = @menu_output.index('Please select boot device:')
        raise Uncertain, 'Incomplete firmware boot menu' unless header

        text = @menu_output.byteslice(header..)
        positioned = positioned_boot_menu_choices(text)
        return positioned unless positioned.empty?

        border_boot_menu_choices
      end

      def positioned_boot_menu_choices(text)
        text.split(/\e\[\d+;\d+H/).drop(1).map { |entry| clean(entry) }.reject(&:empty?)
      end

      def border_boot_menu_choices
        first_border = @menu_output.index('├'.b)
        last_border = @menu_output.index('├'.b, (first_border || 0) + '├'.bytesize)
        raise Uncertain, 'Incomplete firmware boot menu' unless first_border && last_border

        body = @menu_output.byteslice(first_border...last_border)
        body.split('│'.b).drop(1).each_slice(2).map { |entry, _| clean(entry) }
      end

      def usb_boot_match(line)
        line.match(/\bSVVPUFD([12])\b/) if line.start_with?('BdsDxe:')
      end

      def wait_prompt_line(line)
        raise Uncertain, 'EFI key prompt without the matching application/start message' unless @state == :application

        @evidence << line
        @state = :waiting
      end

      # Track the requested UFD and reject ambiguous boot evidence.
      def usb_line(line, number)
        return unless line.match?(/\ABdsDxe: (?:loading|starting|failed to load|failed to start) /)

        verify_usb_number(number)

        @evidence << line
        if line.start_with?('BdsDxe: loading ')
          raise Uncertain, 'Repeated/unexpected USB boot attempt' unless @state == :armed

          @state = :loading
        elsif line.start_with?('BdsDxe: starting ')
          raise Uncertain, 'Unexpected USB start' unless %i[armed loading].include?(@state)

          @state = :started
        elsif denied_usb_boot?(line)
          @state = :denied
        else
          raise Uncertain, "Unexpected USB boot failure: #{line}"
        end
      end

      def verify_usb_number(number)
        return if number == @ufd

        raise Uncertain, "Unexpected UFD #{number} attempted in UFD #{@ufd} round"
      end

      def denied_usb_boot?(line)
        line.match?(/\ABdsDxe: failed to load .*: Access Denied(?: -- rejected probably by Secure Boot)?\z/) &&
          %i[armed loading].include?(@state)
      end

      # Confirm the expected EFI app ran from the selected UFD.
      def application_line(line)
        unless @state == :started && APPS.fetch(line) == @app
          raise Uncertain, "Unexpected application or missing UFD start: #{line}"
        end

        @evidence << line
        @state = :application
      end

      # Finalize a confirmed USB boot or rejection when Windows starts.
      def windows_line(line)
        @evidence << line
        @state = case @state
                 when :denied then :blocked
                 when :key_sent, :menu_selection_sent then :allowed
                 else raise Uncertain, 'Windows started without a complete, correlated EFI outcome'
                 end
      end
    end
  end
end
