# frozen_string_literal: true

module AutoHCK
  class FsCopy
    CONFIG_JSON = 'lib/resultuploaders/fs_copy/fs_copy.json'

    include Helper

    attr_reader :url

    def initialize(project)
      @logger = project.logger

      @config = Json.read_json(CONFIG_JSON, @logger)

      @host_path = @config['host_path']
      base_url = @config['base_url']

      work_path = "auto_hck/#{project.config['repository']}/#{project.engine_tag}/#{project.timestamp}"

      @path = "#{@host_path}/#{work_path}"
      @url = "#{base_url}/#{work_path}" unless base_url.nil?
    end

    def html_url; end

    def handle_exceptions(where)
      yield
    rescue StandardError => e
      @logger.warn("FS #{where} error: #{e.detailed_message}")
      false
    end

    # These methods are intentionally left blank to maintain the interface,
    # as FsCopy does not require this function. It prevents external calls
    # from causing errors while adhering to the expected API structure.
    def ask_token; end

    def connect
      File.exist?(@host_path)
    end

    def create_project_folder
      handle_exceptions(__method__) do
        FileUtils.mkdir_p(@path)
        @logger.info("FS project folder created: #{@url}")
      end
    end

    def upload_file(l_path, r_name)
      handle_exceptions(__method__) do
        r_path = "#{@path}/#{r_name}"
        FileUtils.copy(l_path, r_path)
      end
    end

    def update_file_content(content, r_name)
      handle_exceptions(__method__) do
        r_path = "#{@path}/#{r_name}"
        File.write(r_path, content)
      end
    end

    def delete_file(r_name)
      handle_exceptions(__method__) do
        r_path = "#{@path}/#{r_name}"
        FileUtils.remove(r_path)
        @logger.info("FS file deleted: #{r_path}")
        true
      rescue Errno::ENOENT
        false
      end
    end

    def close; end
  end
end
