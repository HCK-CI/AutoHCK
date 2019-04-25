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

  def connect
    if @token
      @dropbox = DropboxApi::Client.new(@token)
      @logger.error('Dropbox authentication failure') if @dropbox.nil?
    else
      @logger.info('Dropbox token missing')
    end
    @dropbox.nil? ? false : true
  rescue DropboxApi::Errors::HttpError
    @logger.error('Dropbox connection error')
    false
  end

  def create_project_folder
    return if @dropbox.nil?

    @path = '/' + @tag + '-' + @timestamp
    @dropbox.create_folder(@path)
    @dropbox.share_folder(@path)
    @url = @dropbox.create_shared_link_with_settings(@path).url + '&lst='
    @logger.info("Dropbox project folder created: #{@url}")
  rescue StandardError => e
    @logger.error("Dropbox create_project_folder error: #{e.message}")
  end

  def upload_file(l_path, r_name)
    return if @dropbox.nil?

    content = IO.read(l_path)
    r_path = @path + '/' + r_name
    @dropbox.upload(r_path, content)
  rescue StandardError => e
    @logger.error("Dropbox upload_file error: #{e.message}")
  end

  def update_file_content(content, r_name)
    return if @dropbox.nil?

    r_path = @path + '/' + r_name
    @dropbox.upload(r_path, content, mode: 'overwrite')
  rescue StandardError => e
    @logger.error("Dropbox update_file_content error: #{e.message}")
  end

  def close; end
end
