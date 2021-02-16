# frozen_string_literal: true

require './lib/resultuploaders/dropbox'

# AutoHCK module
module AutoHCK
  # ResultUploader
  #
  class ResultUploader
    # UploaderFactory
    #
    class UploaderFactory
      UPLOADERS = {
        dropbox: Dropbox
      }.freeze

      def self.create(type, project)
        UPLOADERS[type].new(project)
      end

      def self.can_create?(type)
        !UPLOADERS[type].nil?
      end
    end

    def initialize(project)
      @project = project
      @connected_uploaders = {}
      @uploaders = {}
      @project.config['result_uploaders'].uniq.collect(&:to_sym).each do |type|
        if UploaderFactory.can_create?(type)
          @uploaders[type] = UploaderFactory.create(type, @project)
        else
          @project.logger.info("Unknown type uploader #{type}, (ignoring)")
        end
      end
    end

    def connect
      @uploaders.each_pair do |type, uploader|
        if uploader.connect
          @connected_uploaders[type] = uploader
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
      return nil unless @connected_uploaders.key?(:dropbox)

      @connected_uploaders[:dropbox].url
    end

    def close
      @connected_uploaders.each_value(&:close)
    end
  end
end
