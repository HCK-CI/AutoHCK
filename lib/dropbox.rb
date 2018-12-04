require 'dropbox_api'

# dropbox class
class Dropbox
  attr_reader :url
  def initialize(project)
    token = ENV['AUTOHCK_DROPBOX_TOKEN']
    @logger = project.logger
    @timestamp = project.timestamp
    @tag = project.tag
    @url = nil
    token ? @dropbox = DropboxApi::Client.new(token) : return
    @dropbox.get_current_account
    @logger.error('Dropbox authentication failure') if @dropbox.nil?
    create_shared_folder
  rescue DropboxApi::Errors::HttpError
    @dropbox = nil
  end

  def create_shared_folder
    return unless @dropbox && !@dropbox.nil?

    @path = '/' + @tag + '-' + @timestamp
    @dropbox.create_folder(@path)
    @dropbox.share_folder(@path)
    @url = @dropbox.create_shared_link_with_settings(@path).url + '&lst='
    @logger.info("Dropbox shared folder: #{@url}")
  end

  def upload(local_path, rename = nil)
    return unless @dropbox && !@dropbox.nil? && @url

    file_name = if rename.nil?
                  File.basename(local_path)
                else
                  rename + File.extname(local_path)
                end
    file_content = IO.read(local_path)
    remote_path = @path + '/' + file_name
    @dropbox.upload(remote_path, file_content)
  end

  def upload_text(content, file_name)
    return unless @dropbox && !@dropbox.nil? && @url

    remote_path = @path + '/' + file_name
    @dropbox.upload(remote_path, content, mode: 'overwrite')
  end
end
