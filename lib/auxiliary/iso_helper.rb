# frozen_string_literal: true

require './lib/auxiliary/host_helper'

# AutoHCK module
module AutoHCK
  # Helper module
  module Helper
    def create_iso(iso_path, dir_paths)
      run_cmd(['mkisofs', '-iso-level', '4', '-l', '-R', '-udf', '-D',
               '-o', iso_path] + dir_paths)
    end
  end
end
