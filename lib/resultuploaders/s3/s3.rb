# frozen_string_literal: true

module AutoHCK
  # S3 class for managing interactions with S3-compatible storage services.
  # This class is designed to work with services that are compatible with the S3 API,
  # including AWS S3 and Alibaba Cloud OSS.
  class S3
    CONFIG_JSON = 'lib/resultuploaders/s3/s3.json'
    INDEX_FILE_NAME = 'index.html'

    include Helper

    # Provides read access to the URL for the index.html file.
    #
    # In the context of S3 compatibility, there is no concept of folders.
    # The `url` will point to an index.html file that records the paths of all files.
    # This allows `index.html` to be displayed directly in HTML format.
    #
    # Note: While AWS S3 supports this behavior of rendering HTML files directly,
    # not all S3-compatible storage services do. For example, Alibaba Cloud OSS
    # has security restrictions on its default domain that may require files to be
    # downloaded rather than rendered directly, thus preventing HTML files from being displayed.
    attr_reader :url

    def initialize(project)
      tag = project.engine_tag
      timestamp = project.timestamp
      repo = project.config['repository']
      @path = "#{repo}/CI/#{tag}-#{timestamp}"

      @logger = project.logger

      @bucket = new_bucket

      @index_obj = @bucket.object("#{@path}/#{INDEX_FILE_NAME}")
      @index_template = ERB.new(File.read('lib/templates/index.html.erb'))
      @filenames = []
    end

    def html_url; end

    # The current exception handling only logs errors without any additional recovery or fallback mechanisms.
    # Rescue only Aws::Errors::ServiceError and Seahorse::Client::NetworkingError,
    # as rescuing StandardError may suppress other programming errors (e.g., NoMethodError).
    # This approach focuses on handling networking errors and those reported by the storage service.
    # Future enhancements may include more robust error handling strategies and raising a special error class
    # instead of just logging when we need to handle errors in callers.
    def handle_exceptions(where)
      yield
    rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError => e
      @logger.warn("S3 #{where} error: #{e.detailed_message}")
      false
    end

    # These methods are intentionally left blank to maintain the interface,
    # as S3-compatible does not require this function. It prevents external calls
    # from causing errors while adhering to the expected API structure.
    def ask_token; end

    def connect
      true
    end

    def create_project_folder
      handle_exceptions(__method__) do
        generate_index
        @url = @index_obj.public_url
        @logger.info("S3 project folder created: #{@url}")
        true
      end
    end

    def upload_file(l_path, r_name)
      handle_exceptions(__method__) do
        r_path = "#{@path}/#{r_name}"
        type = 'text/html' if r_name.end_with?('.html')
        obj = @bucket.object(r_path)
        obj.upload_file(l_path, content_type: type)
        @filenames << r_name
        generate_index
        @logger.info("S3 file uploaded: #{r_path}")
        true
      end
    end

    def update_file_content(content, r_name)
      handle_exceptions(__method__) do
        r_path = "#{@path}/#{r_name}"
        obj = @bucket.object(r_path)
        obj.put(body: content)
        @logger.info("S3 file content updated: #{r_path}")
        true
      end
    end

    def delete_file(r_name)
      handle_exceptions(__method__) do
        r_path = "#{@path}/#{r_name}"
        obj = @bucket.object(r_path)
        obj.delete
        @filenames.delete(r_name)
        generate_index
        @logger.info("S3 file deleted: #{r_path}")
        true
      end
    end

    def close; end

    private

    def new_bucket
      access_key_id = ENV.fetch('AUTOHCK_S3_ACCESS_KEY_ID')
      secret_access_key = ENV.fetch('AUTOHCK_S3_SECRET_ACCESS_KEY')

      config = Json.read_json(CONFIG_JSON, @logger)
      region = config['region']
      bucket_name = config['bucket_name']
      endpoint = config['endpoint']

      s3_resource = Aws::S3::Resource.new(
        access_key_id:,
        secret_access_key:,
        region:,
        endpoint: "https://#{endpoint}"
      )

      s3_resource.bucket(bucket_name)
    end

    def generate_index
      handle_exceptions(__method__) do
        index_data = {
          'path' => @path,
          'filenames' => @filenames,
          'bucket' => @bucket
        }
        @index_obj.put(body: @index_template.result_with_hash(index_data), content_type: 'text/html')
        true
      end
    end
  end
end
