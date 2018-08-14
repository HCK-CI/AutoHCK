require './lib/dropbox_api'

# dropbox class
class Dropbox
  attr_reader :url
  def initialize(project)
    token = project.config['dropbox_token']
    @logger = project.logger
    @timestamp = project.timestamp
    @tag = project.tag
    token ? @dropbox = DropboxAPI.new(token) : return
    @logger.error('Dropbox authentication failure') unless @dropbox.connected?
    create_shared_folder
  end

  def create_shared_folder
    return unless @dropbox && @dropbox.connected?
    @dropbox.create_folder("#{@tag}-#{@timestamp}")
    @logger.info("Dropbox shared folder: #{@dropbox.url}")
  end

  def upload(file_path, file_name = nil)
    return unless @dropbox && @dropbox.connected?
    @dropbox.upload_file(file_path, file_name)
  end

  def upload_text(content, file_name)
    return unless @dropbox && @dropbox.connected?
    @dropbox.upload_text(content, file_name)
  end
end
