# frozen_string_literal: true

require 'fileutils'
require 'zip'

# AutoHCK module
module AutoHCK
  # Helper module
  module Helper
    def create_zip_from_directory(zip_path, dir_path)
      Zip::File.open(zip_path, Zip::File::CREATE) do |zip_file|
        Dir["#{dir_path}/**/**"].each do |file|
          zip_file.add(file.sub("#{dir_path}/", ''), file)
        end
      end
    end
  end
end
