# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # dropbox class
  class Dropbox
    TOKEN_JSON = 'lib/resultuploaders/dropbox/token.json'
    CONFIG_JSON = 'lib/resultuploaders/dropbox/dropbox.json'

    include Helper

    attr_reader :url

    def initialize(project)
      @tag = project.engine_tag
      @timestamp = project.timestamp
      @logger = project.logger
      @repo = project.config['repository']

      @config = Json.read_json(CONFIG_JSON, @logger)

      @client_id = ENV.fetch('AUTOHCK_DROPBOX_CLIENT_ID')
      @client_secret = ENV.fetch('AUTOHCK_DROPBOX_CLIENT_SECRET')

      @action_retries = @config['action_retries']
      @action_retry_sleep = @config['action_retry_sleep']

      @authenticator = DropboxApi::Authenticator.new(@client_id, @client_secret)

      @dropbox = nil
      @url = nil
    end

    def html_url; end

    # handle_exceptions has different logic for different exceptions,
    # so this method can not be simplified without dirty workarounds
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def handle_exceptions(where)
      retries ||= 0

      if @dropbox.nil?
        @logger.warn("Dropbox connection error, ignoring #{where}")
      else
        yield
      end
    rescue Faraday::ConnectionFailed, OAuth2::ConnectionError
      @logger.warn("Dropbox connection lost while #{where}")
      raise unless (retries += 1) < @action_retries

      @logger.info('Trying to re-establish the Dropbox connection after delay')
      sleep @action_retry_sleep
      connect
      retry
    rescue DropboxApi::Errors::TooManyWriteOperationsError
      @logger.warn("Dropbox API failed #{where}")
      raise unless (retries += 1) < @action_retries

      @logger.info('Trying to re-send request after delay')
      sleep @action_retry_sleep
      retry
    rescue StandardError => e
      @logger.warn("Dropbox #{where} error: (#{e.class}) #{e.message}")
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    def ask_token
      url = @authenticator.auth_code.authorize_url(token_access_type: 'offline')
      @logger.info("Navigate to #{url}")
      @logger.info('Please enter authorization code')

      code = gets.chomp
      @token = @authenticator.auth_code.get_token(code)

      save_token(@token)
    end

    def save_token(token)
      @logger&.info('Dropbox token to be saved in the local file')

      File.write(TOKEN_JSON, token.to_hash.to_json)
    end

    def load_token
      @logger.info('Loading Dropbox token from the local file')

      return nil unless File.exist?(TOKEN_JSON)

      begin
        hash = JSON.parse(File.read(TOKEN_JSON))
      rescue StandardError => e
        @logger.warn("Loading Dropbox token error: (#{e.class}) #{e.message}")

        return nil
      end

      @token = OAuth2::AccessToken.from_hash(@authenticator, hash)
    end

    def connect
      load_token if @token.nil?

      if @token
        @dropbox = DropboxApi::Client.new(
          access_token: @token,
          on_token_refreshed: lambda { |new_token|
            save_token(new_token)
          }
        )
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
        content = File.read(l_path)
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
