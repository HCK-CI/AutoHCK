# frozen_string_literal: true

require './lib/auxiliary/host_helper'

# AutoHCK module
module AutoHCK
  # Helper module
  module Helper
    def create_iso(iso_path, dir_paths, exclude_list = [])
      exclude_args = exclude_list.map { |v| "-exclude=#{v}" }

      run_cmd([
        'mkisofs -iso-level 4 -l -R -udf -D -allow-limited-size',
        *exclude_args, '-o', iso_path, *dir_paths
      ].join(' '))
    end
  end
end
