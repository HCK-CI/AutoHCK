# frozen_string_literal: true

require 'active_support'
require 'active_support/core_ext/string/inflections'

# AutoHCK module
module AutoHCK
  # ResultUploader
  #
  class ResultUploader
    # UploaderFactory
    #
    class UploaderFactory
      UPLOADERS = Dir.each_child(__dir__).filter_map do |uploader_name|
        full_path = "#{__dir__}/#{uploader_name}"
        next unless File.directory? full_path

        file = "#{full_path}/#{uploader_name}.rb"
        require file
        # Convert 'result_uploader' (file name) -> 'ResultUploader' (class name)
        class_name = uploader_name.camelize
        # Convert 'ResultUploader' (class name) -> ResultUploader (declared constant)
        # or
        # Convert 'ResultUploader' (class name) -> AutoHCK::ResultUploader (declared constant)
        [uploader_name, AutoHCK.const_get(class_name)]
      end.to_h.freeze

      def self.create(type, project)
        UPLOADERS[type].new(project)
      end

      def self.can_create?(type)
        !UPLOADERS[type].nil?
      end
    end

    def initialize(scope, project)
      @scope = scope
      @project = project
      @connected_uploaders = {}
      @uploaders = {}
      @project.config['result_uploaders'].uniq.each do |type|
        if UploaderFactory.can_create?(type)
          @uploaders[type] = UploaderFactory.create(type, @project)
        else
          @project.logger.info("Unknown type uploader #{type}, (ignoring)")
        end
      end
    end

    def ask_token
      @uploaders.each_value(&:ask_token)
    end

    def connect
      @uploaders.each_pair do |type, uploader|
        if uploader.connect
          @connected_uploaders[type] = uploader
          @scope << uploader
        else
          @project.logger.info("#{type} connection failed, (ignoring)")
        end
      end
    end

    def create_project_folder
      @connected_uploaders.each_value(&:create_project_folder)
    end

    def delete_file(r_name)
      @connected_uploaders.each_value do |uploader|
        uploader.delete_file(r_name)
      end
    end

    def upload_file(l_path, r_name)
      @connected_uploaders.each_value do |uploader|
        uploader.upload_file(l_path, r_name)
      end
    end

    def update_file_content(content, r_name)
      @connected_uploaders.each_value do |uploader|
        uploader.update_file_content(content, r_name)
      end
    end

    def url
      @connected_uploaders.values.filter_map(&:url).first
    end

    def html_url
      @connected_uploaders.values.filter_map(&:html_url).first
    end
  end
end
