# frozen_string_literal: true

module AutoHCK
  class HCKTest
    # Track one USB boot attempt and classify its firmware outcome.
    class SecureBootSerialRound
      class Uncertain < StandardError; end

      APPS = {
        'Welcome to the pressanykey1 efi app' => 'pressanykey1',
        'Welcome to the pressanykey2 efi app' => 'pressanykey2',
        'Welcome to the pressanykey MSFT test-signed efi app' => 'msft_test_pressanykey'
      }.freeze
      WAIT_PROMPT = 'Press any key to continue...'
      MAX_READ = 1024 * 1024
      TIMEOUT = 600

      attr_reader :id, :ufd, :app, :session, :state, :reason, :offset, :evidence

      def initialize(id:, ufd:, app:, path:, session:)
        @id, @ufd, @app, @path, @session = id, ufd, app, path, session
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
        unless identity(file.stat) == @identity && file.size >= @offset && anchor(file) == @anchor
          raise Uncertain, 'Serial log replaced, truncated, or rewritten (including truncate-and-regrow)'
        end

        file.seek(@offset)
        bytes = file.read(MAX_READ + 1) || ''.b
        raise Uncertain, 'Serial backlog exceeded the per-poll limit' if bytes.bytesize > MAX_READ

        @offset += bytes.bytesize
        @anchor = anchor(file)
        @pending << bytes
        consume_lines
        raise Uncertain, 'Unterminated serial line exceeded the limit' if @pending.bytesize > MAX_READ
      end

      # Normalize firmware text before checking expected messages.
      def clean(line)
        line.gsub(/\e\[[0-?]*[ -\/]*[@-~]/, '').strip
      end

      # Process complete firmware messages while preserving unfinished output.
      def consume_lines
        while (ending = @pending.index(/[\r\n]/))
          line = @pending.slice!(0, ending + 1)
          consume(clean(line))
        end
        # Recognize the EFI app's input prompt promptly.
        return unless clean(@pending) == WAIT_PROMPT

        consume(WAIT_PROMPT)
        @pending.clear
      end

      # Classify expected firmware messages for the active boot attempt.
      def consume(line)
        return if line.empty?

        if line.start_with?('BdsDxe:') && (match = line.match(/\bSVVPUFD([12])\b/))
          usb_line(line, match[1].to_i)
        elsif APPS.key?(line)
          application_line(line)
        elsif line == WAIT_PROMPT
          raise Uncertain, 'EFI key prompt without the matching application/start message' unless @state == :application

          @evidence << line
          @state = :waiting
        elsif line.match?(/\ABdsDxe: starting .*"Windows Boot Manager"/)
          windows_line(line)
        elsif line.start_with?('Welcome to the pressanykey')
          raise Uncertain, "Unrecognized EFI application: #{line}"
        end
      end

      # Track the requested UFD and reject ambiguous boot evidence.
      def usb_line(line, number)
        return unless line.match?(/\ABdsDxe: (?:loading|starting|failed to load|failed to start) /)

        raise Uncertain, "Unexpected UFD #{number} attempted in UFD #{@ufd} round" unless number == @ufd

        @evidence << line
        if line.start_with?('BdsDxe: loading ')
          raise Uncertain, 'Repeated/unexpected USB boot attempt' unless @state == :armed

          @state = :loading
        elsif line.start_with?('BdsDxe: starting ')
          raise Uncertain, 'Unexpected USB start' unless %i[armed loading].include?(@state)

          @state = :started
        elsif line.match?(/\ABdsDxe: failed to load .*: Access Denied(?: -- rejected probably by Secure Boot)?\z/) &&
              %i[armed loading].include?(@state)
          @state = :denied
        else
          raise Uncertain, "Unexpected USB boot failure: #{line}"
        end
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
                 when :key_sent then :allowed
                 else raise Uncertain, 'Windows started without a complete, correlated EFI outcome'
                 end
      end
    end
  end
end
