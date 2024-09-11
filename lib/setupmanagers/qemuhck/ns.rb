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
                nsenter_argv = %W[nsenter -m -n --preserve-credentials -t #{pid} -w#{chdir}]
                nsenter_argv << '-U' unless Process.euid.zero?
                system(*nsenter_argv, '--', *argv)
                exit $CHILD_STATUS.exitstatus
              end
            ensure
              pid_file.release
            end
          ensure
            pid_file.close
          end
        end
      end
    end
  end
end
