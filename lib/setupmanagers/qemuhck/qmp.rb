# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # QemuMachine class
  class QemuMachine
    # QMP class
    class QMP
      # Internal marker stored on cached events; stripped before returning to callers.
      EVENT_GEN_KEY = '_autohck_gen'

      attr_reader :socket

      def initialize(scope, name, logger)
        @name = name
        @logger = logger
        @negotiated = false
        @events = []
        @generation = 0
        @logger.info("Initiating QMP session for #{name}")
        @socket, @socket_internal = UNIXSocket.pair
        scope << @socket
        scope << @socket_internal
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
        unless @negotiated
          send_cmd 'qmp_capabilities'
          @negotiated = true
        end

        # Bump the epoch on every command (including the internal query-status
        # pokes issued from wait_for_new_event). Events are tagged with the
        # generation current when they are read off the socket, and wait_for
        # keeps everything with generation >= the epoch of its triggering
        # command, so mid-wait bumps don't drop still-pending events.
        @generation += 1
        send_cmd(cmd, arguments)
      end

      # Accept only events from the current/last command generation onward.
      # Stale same-named events (e.g. leftover DEVICE_DELETED from a prior
      # hotplug cycle) have a lower generation and are ignored — without
      # draining a valid early event that already arrived for this command.
      #
      # The cache is checked first, before touching the socket: if the event
      # already arrived for this command it is returned without a round-trip to
      # QEMU (which may already be gone, e.g. right after quit/powerdown).
      # Otherwise wait_for_new_event blocks, and its polling loop pokes
      # query-status so guest-triggered events (e.g. GUEST_PANICKED) buffered in
      # QEMU are flushed onto the socket.
      def wait_for(name, accepted, timeout = 60)
        since = @generation

        cached = find_cached_event(name, accepted, since)
        return cached if cached

        wait_for_new_event(name, accepted, since, timeout)
      end

      private

      def cache_event(response)
        @events << response.merge(EVENT_GEN_KEY => @generation)
      end

      def public_event(response)
        response.except(EVENT_GEN_KEY)
      end

      def matching_event?(response, name, accepted, since)
        response[EVENT_GEN_KEY].to_i >= since && accepted.include?(response[name])
      end

      def find_cached_event(name, accepted, since)
        index = @events.index { |e| matching_event?(e, name, accepted, since) }
        return nil unless index

        public_event(@events.delete_at(index))
      end

      def wait_for_new_event(name, accepted, since, timeout)
        Timeout.timeout(timeout) do
          loop do
            if @socket_internal.wait_readable(2)
              response = JSON.parse(@socket_internal.readline)
              @logger.debug("Received QMP message: #{response}")

              if response.key?('event')
                cache_event(response)
                cached = find_cached_event(name, accepted, since)
                return cached if cached
              end

              raise(QMPError, response['error'].to_s) if response.key?('error')
            else
              # Force QEMU to flush pending events (guest-side crashes, etc.).
              run_cmd('query-status')

              cached = find_cached_event(name, accepted, since)
              return cached if cached
            end
          end
        end
      end

      def send_cmd(cmd, arguments = nil)
        cmd_hash = { 'execute' => cmd }
        cmd_hash['arguments'] = arguments if arguments
        @socket_internal.write JSON.dump(cmd_hash)
        @socket_internal.flush

        loop do
          response = JSON.parse(@socket_internal.readline)
          if response.key?('event')
            cache_event(response)
            next
          end
          break response['return'] if response.key?('return')
          raise(QMPError, response['error'].to_s) if response.key?('error')
        end
      end
    end
  end
end
