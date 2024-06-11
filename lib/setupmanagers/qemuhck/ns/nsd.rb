# frozen_string_literal: true

module AutoHCK
  class QemuHCK
    module Ns
      class Nsd
        def initialize(**kwargs)
          signal = begin
            IO.pipe do |read, write|
              @pid = spawn("#{__dir__}/../../../../bin/nsd",
                           out: write, pgroup: 0, **kwargs)
              write.close
              read.read 1
            end
          rescue StandardError
            unless @pid.nil?
              kill
              wait
            end

            raise
          end

          exit wait.exitstatus if signal.nil?
        end

        def detach
          Process.detach @pid
        end

        def kill
          Process.kill 'SIGKILL', -@pid
        end

        def to_s
          @pid.to_s
        end

        def wait
          Process.wait2(@pid)[1]
        end
      end
    end
  end
end
