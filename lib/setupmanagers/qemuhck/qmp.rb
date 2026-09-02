# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # QemuMachine class
  class QemuMachine
    # QMP class
    class QMP
      attr_reader :socket

      # Internal marker stored on cached events
      EVENT_GEN_KEY = '_autohck_gen'
      WAIT_EVENT_READABLE = 2

      def initialize(scope, name, logger)
        @name = name
        @logger = logger
        @mutex = Mutex.new
        @response_ready = ConditionVariable.new
        @negotiated = false
        @responses = {}
        @generation = 0
        @logger.info("Initiating QMP session for #{name}")
        @socket, @socket_internal = UNIXSocket.pair
        scope << @socket
        scope << @socket_internal
        scope << ThreadScope.new(Thread.new { response_reader })
      end

      def quit
        @logger.info("Sending quit signal to #{@name} via QMP")
        run_cmd('quit')
      end

      def powerdown
        @logger.info("Sending powerdown signal to #{@name} via QMP")
        run_cmd('system_powerdown')
      end

      def run_cmd(cmd, arguments = nil)
        generation = @mutex.synchronize do
          # Drop the cache for the previous generation and increment the generation counter
          @responses[@generation - 1] = [] if @generation >= 1
          @generation += 1
        end
        negotiate
        send_cmd(cmd, arguments, generation)
      end

      def save_response_cache(response)
        @mutex.synchronize do
          @responses[@generation] ||= []
          response[EVENT_GEN_KEY] = @generation
          @responses[@generation] << response
          @response_ready.broadcast
        end
      end

      def response_reader
        @logger.info("Starting QMP response reader thread for #{@name}")
        loop do
          response = JSON.parse(@socket_internal.readline)
          generation = @mutex.synchronize { @generation }
          @logger.debug("Received QMP message (generation: #{generation}): #{response}")
          save_response_cache(response)
        end
      end

      # accepted is an array of acceptable values; this returns as soon as
      # any one of them is seen.
      def wait_for(name, accepted, timeout = 60)
        Timeout.timeout(timeout) do
          loop do
            cached = find_cached_event(name, accepted)
            return cached if cached

            # If we don't have a cached event, we need to make sure the QEMU will send us an event.
            # If we haven't received any events in the last WAIT_EVENT_READABLE seconds,
            # we need to ask QEMU to send us one.
            send_cmd('query-status') unless @socket_internal.wait_readable(WAIT_EVENT_READABLE)
          end
        end
      end

      def negotiate
        @mutex.synchronize { return if @negotiated }

        send_cmd 'qmp_capabilities'
        @mutex.synchronize { @negotiated = true }
      end

      private

      def find_cached_event(name, accepted, since_generation = nil)
        @mutex.synchronize do
          since_generation ||= @generation
          find_cached_event_locked(name, accepted, since_generation)
        end
      end

      def find_cached_event_locked(name, accepted, since_generation)
        (since_generation..@generation).reverse_each do |gen|
          next if @responses[gen].nil?

          index = @responses[gen].index { |e| accepted.include?(e[name]) && e[EVENT_GEN_KEY] >= since_generation }
          return @responses[gen].delete_at(index) if index
        end

        nil
      end

      def current_command_response_locked(generation)
        return nil if @responses[generation].nil?

        index = @responses[generation].index { |e| e.key?('return') || e.key?('error') }
        @responses[generation].delete_at(index) if index
      end

      def wait_for_command_response(generation)
        @mutex.synchronize do
          loop do
            command_response = current_command_response_locked(generation)
            break command_response if command_response

            @response_ready.wait(@mutex, WAIT_EVENT_READABLE)
          end
        end
      end

      def send_cmd(cmd, arguments = nil, generation = nil)
        generation = @mutex.synchronize { generation || @generation }
        cmd_hash = { 'execute' => cmd }
        cmd_hash['arguments'] = arguments if arguments
        @logger.debug("Sending QMP command (generation: #{generation}): #{cmd_hash}")
        @socket_internal.write JSON.dump(cmd_hash)
        @socket_internal.flush

        loop do
          response = wait_for_command_response(generation)

          break response['return'] if response.key?('return')
          raise(QMPError, response['error'].to_s) if response.key?('error')
        end
      end
    end
  end
end
