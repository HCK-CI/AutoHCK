# frozen_string_literal: true

module AutoHCK
  class QemuHCK
    module Ns
      extend AutoloadExtension

      autoload_relative :Hostfwd, 'ns/hostfwd'
      autoload_relative :Nsd, 'ns/nsd'
      autoload_relative :PidFile, 'ns/pid_file'

      def self.enter(workspace, chdir, config, *argv)
        Signal.trap 'INT', 'IGNORE'

        Thread.handle_interrupt Object => :never do
          pid_file = PidFile.new(workspace)
          begin
            pid = pid_file.acquire
            begin
              Thread.handle_interrupt Object => :immediate do
                perform(pid, chdir, config, *argv)
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

      def self.perform(pid, chdir, config, *argv)
        ext_bridge = config['control_bridge_external']
        run_id = config['run_id']

        unless ext_bridge.nil? || run_id.nil?
          # You need to configure system to allow passwordless sudo for ns_veth
          sudo = Process.euid.zero? ? [] : ['sudo']
          cmd = %W[#{sudo} #{chdir}/bin/ns_veth host #{pid} #{run_id} #{ext_bridge}]
          system(cmd.join(' '))
          raise "[ns.rb] #{cmd.join(' ')}: command failed" unless $CHILD_STATUS.success?

          nsexec(pid, chdir, 'bin/ns_veth', 'ns')
        end

        nsenter(pid, chdir, *argv)
      end

      def self.nsenter_argv(pid, chdir)
        argv = %W[nsenter -m -n --preserve-credentials -t #{pid} -w#{chdir}]
        argv << '-U' unless Process.euid.zero?
        argv
      end

      def self.nsexec(pid, chdir, *argv)
        command = [*nsenter_argv(pid, chdir), '--', *argv]
        $stderr.write "[ns.rb] Running (system): #{command.join(' ')}\n"
        system(*command)
        raise "[ns.rb] #{command.join(' ')}: command failed" unless $CHILD_STATUS.success?
      end

      def self.nsenter(pid, chdir, *argv)
        command = [*nsenter_argv(pid, chdir), '--', *argv]
        $stderr.write "[ns.rb] Running (system): #{command.join(' ')}\n"
        system(*command)
        exit $CHILD_STATUS.exitstatus
      end

      private_class_method :nsenter_argv, :nsenter, :nsexec, :perform
    end
  end
end
