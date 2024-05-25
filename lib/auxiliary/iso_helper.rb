# frozen_string_literal: true

require './lib/auxiliary/host_helper'

# AutoHCK module
module AutoHCK
  # Helper module
  module Helper
    def create_iso(iso_path, dir_paths, exclude_list = [])
      exclude_args = exclude_list.flat_map { ['-old-exclude', _1] }

      run_cmd(*%w[xorriso -as mkisofs -iso-level 4 -J -l -D -N -joliet-long -relaxed-filenames -V INSTALLER],
              *exclude_args, '-o', iso_path, *dir_paths)
    end
  end
end
