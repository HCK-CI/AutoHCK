# typed: true
# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # Helper module
  module Helper
    extend T::Sig

    sig { params(iso_path: Pathname, dir_paths: T::Array[Pathname], exclude_list: T::Array[String]).void }
    def create_iso(iso_path, dir_paths, exclude_list = [])
      exclude_args = exclude_list.flat_map { ['-old-exclude', _1] }

      dir_paths_strs = dir_paths.map(&:to_s)
      @logger.info("Creating ISO image at #{iso_path} from #{dir_paths_strs} with excludes: #{exclude_list}")

      argv = %w[xorriso -as mkisofs -iso-level 4 -J -l -D -N -joliet-long -relaxed-filenames -V INSTALLER] +
             exclude_args + ['-o', iso_path.to_s] + dir_paths_strs
      run_cmd(*T.unsafe(argv))
    end
  end
end
