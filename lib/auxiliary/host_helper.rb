# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # Helper module
  module Helper
    def run_cmd(...)
      ResourceScope.open { CmdRun.new(_1, @logger, ...) }
    end

    def file_gsub(src, dst, gsub_list)
      content = File.read(src)
      gsub_list.each do |k, v|
        content = content.gsub(k, v)
      end
      File.write(dst, content)
    end
  end
end
