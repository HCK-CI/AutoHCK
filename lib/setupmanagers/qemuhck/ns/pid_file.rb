# frozen_string_literal: true

module AutoHCK
  class QemuHCK
    module Ns
      class PidFile
        def initialize(path)
          @path = path
          @file = File.open(File.join(path, 'pid'), File::CREAT | File::RDWR)
        end

        def close
          @file.close
        end

        def acquire
          str = loop do
            str = lock(File::LOCK_SH)
            break str unless str.empty?

            unlock

            if lock(File::LOCK_EX).empty?
              nsd = Nsd.new chdir: @path
              nsd.detach
              @file.write nsd.to_s
              @file.rewind
            end

            unlock
          end

          @file.rewind
          str
        end

        def release
          unlock

          str = lock(File::LOCK_EX | File::LOCK_NB)
          return if str.nil?

          begin
            Process.kill 'SIGKILL', -str.to_i unless str.empty?
            @file.truncate 0
          ensure
            unlock
          end
        end

        private

        def lock(flags)
          @file.flock(flags) ? @file.read : nil
        end

        def unlock
          @file.flock File::LOCK_UN
        end
      end
    end
  end
end
