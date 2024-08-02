# frozen_string_literal: true

module AutoHCK
  class QemuHCK
    module Ns
      # Hostfwd is a class that holds ports forwarded for a run.
      class Hostfwd
        include Helper

        def initialize(logger, workspace_path, ports)
          @logger = logger
          @workspace_path = workspace_path
          @ids = []
          begin
            ports.each { @ids << slirp('add_hostfwd', _1.to_s)['id'] }
          rescue StandardError
            close
          end
        end

        def close
          slirp 'remove_hostfwd', @ids.pop.to_s until @ids.empty?
        end

        private

        def slirp(*args)
          File.open('/tmp', File::RDWR | File::TMPFILE) do |out|
            run_cmd('bin/slirp', '-w', @workspace_path, *args, out:)
            out.rewind
            JSON.parse(out.read)['return']
          end
        end
      end
    end
  end
end
