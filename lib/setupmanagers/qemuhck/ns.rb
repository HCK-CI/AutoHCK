# frozen_string_literal: true

module AutoHCK
  class QemuHCK
    module Ns
      extend AutoloadExtension

      autoload_relative :Hostfwd, 'ns/hostfwd'
      autoload_relative :Nsd, 'ns/nsd'
      autoload_relative :PidFile, 'ns/pid_file'

      def self.enter(workspace, chdir, *argv)
        Signal.trap 'INT', 'IGNORE'

        Thread.handle_interrupt Object => :never do
          pid_file = PidFile.new(workspace)
          begin
            pid = pid_file.acquire
            begin
              Thread.handle_interrupt Object => :immediate do
                system(*nsenter_argv(pid, chdir), '--', *argv)
                exit $CHILD_STATUS.exitstatus
              end
            ensure
              begin
                pid_file.release
              rescue Errno::ESRCH
                # Ignore "No such process" error
                # This can happened if AutoHCK was interrupted
                # and "nsenter" already exited
              end
            end
          ensure
            pid_file.close
          end
        end
      end

      def self.nsenter_argv(pid, chdir)
        argv = %W[nsenter -m -n --preserve-credentials -t #{pid} -w#{chdir}]
        argv << '-U' unless Process.euid.zero?
        argv
      end

      private_class_method :nsenter_argv
    end
  end
end
