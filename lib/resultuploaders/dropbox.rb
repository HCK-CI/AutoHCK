# frozen_string_literal: true

require 'dropbox_api'

# AutoHCK module
module AutoHCK
  # dropbox class
  class Dropbox
    ACTION_RETRIES = 5
    ACTION_RETRY_SLEEP = 10

    attr_reader :url

    def initialize(project)
      @tag = project.engine.tag
      @timestamp = project.timestamp
      @logger = project.logger
      @repo = project.config['repository']
      @token = ENV['AUTOHCK_DROPBOX_TOKEN']
      @dropbox = nil
      @url = nil
    end

    def handle_exceptions(where)
      retries ||= 0

      if @dropbox.nil?
        @logger.warn("Dropbox connection error, ignoring #{where}")
      else
        yield
      end
    rescue Faraday::ConnectionFailed
      @logger.warn("Dropbox connection lost while #{where}")
      raise unless (retries += 1) < ACTION_RETRIES

      @logger.info('Trying to re-establish the Dropbox connection')
      connect
      retry
    rescue DropboxApi::Errors::TooManyWriteOperationsError
      @logger.warn("Dropbox API failed #{where}")
      raise unless (retries += 1) < ACTION_RETRIES

      @logger.info('Trying to re-send request after delay')
      sleep ACTION_RETRY_SLEEP
      retry
    rescue StandardError => e
      @logger.warn("Dropbox #{where} error: (#{e.class}) #{e.message}")
    end

    def connect
      if @token
        @dropbox = DropboxApi::Client.new(@token)
        @logger.warn('Dropbox authentication failure') if @dropbox.nil?
      else
        @logger.info('Dropbox token missing')
      end
      !@dropbox.nil?
    rescue DropboxApi::Errors::HttpError
      @logger.warn('Dropbox connection error')
      false
    end

    def create_project_folder
      handle_exceptions(__method__) do
        @path = "/#{@repo}/CI/#{@tag}-#{@timestamp}"
        @dropbox.create_folder(@path)
        @dropbox.share_folder(@path)
        @url = "#{@dropbox.create_shared_link_with_settings(@path).url}&lst="
        @logger.info("Dropbox project folder created: #{@url}")
      end
    end

    def upload_file(l_path, r_name)
      handle_exceptions(__method__) do
        content = IO.read(l_path)
        r_path = "#{@path}/#{r_name}"
        @dropbox.upload(r_path, content)
      end
    end

    def update_file_content(content, r_name)
      handle_exceptions(__method__) do
        r_path = "#{@path}/#{r_name}"
        @dropbox.upload(r_path, content, mode: 'overwrite')
      end
    end

    def delete_file(r_name)
      handle_exceptions(__method__) do
        r_path = "#{@path}/#{r_name}"
        @dropbox.delete(r_path)
        @logger.info("Dropbox file deleted: #{r_path}")
        true
      rescue DropboxApi::Errors::NotFoundError
        false
      end
    end

    def close; end
  end
end
