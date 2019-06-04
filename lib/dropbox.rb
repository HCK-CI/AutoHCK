# frozen_string_literal: true

require 'dropbox_api'

# dropbox class
class Dropbox
  attr_reader :url
  def initialize(project)
    @tag = project.tag
    @timestamp = project.timestamp
    @logger = project.logger
    @token = ENV['AUTOHCK_DROPBOX_TOKEN']
    @dropbox = nil
    @url = nil
  end

  def handle_exceptions(where)
    if @dropbox.nil?
      @logger.warn("Dropbox connection error, ignoring #{where}")
    else
      yield
    end
  rescue Faraday::ConnectionFailed
    @logger.warn("Dropbox connection lost while #{where}")
    @logger.info('Trying to re-establish the Dropbox connection')
    connect
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
    @dropbox.nil? ? false : true
  rescue DropboxApi::Errors::HttpError
    @logger.warn('Dropbox connection error')
    false
  end

  def create_project_folder
    handle_exceptions(__method__) do
      @path = '/' + @tag + '-' + @timestamp
      @dropbox.create_folder(@path)
      @dropbox.share_folder(@path)
      @url = @dropbox.create_shared_link_with_settings(@path).url + '&lst='
      @logger.info("Dropbox project folder created: #{@url}")
    end
  end

  def upload_file(l_path, r_name)
    handle_exceptions(__method__) do
      content = IO.read(l_path)
      r_path = @path + '/' + r_name
      @dropbox.upload(r_path, content)
    end
  end

  def update_file_content(content, r_name)
    handle_exceptions(__method__) do
      r_path = @path + '/' + r_name
      @dropbox.upload(r_path, content, mode: 'overwrite')
    end
  end

  def delete_file(r_name)
    handle_exceptions(__method__) do
      begin
        r_path = @path + '/' + r_name
        @dropbox.delete(r_path)
        @logger.info("Dropbox file deleted: #{r_path}")
        true
      rescue DropboxApi::Errors::NotFoundError
        false
      end
    end
  end

  def close; end
end
