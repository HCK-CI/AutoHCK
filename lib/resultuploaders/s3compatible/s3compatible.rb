# frozen_string_literal: true

require 'aws-sdk-s3'
require './lib/auxiliary/json_helper'

# AutoHCK module
module AutoHCK
  # S3compatible class for managing interactions with S3-compatible storage services.
  # This class is designed to work with services that are compatible with the S3 API,
  # including AWS S3 and Alibaba Cloud OSS.
  class S3compatible
    CONFIG_JSON = 'lib/resultuploaders/s3compatible/s3compatible.json'
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
      @tag = project.engine_tag
      @timestamp = project.timestamp
      @logger = project.logger
      @repo = project.config['repository']
      @config = Json.read_json(CONFIG_JSON, @logger)

      @access_key_id = ENV.fetch('AUTOHCK_S3COMPATIBLE_ACCESS_KEY_ID')
      @secret_access_key = ENV.fetch('AUTOHCK_S3COMPATIBLE_SECRET_ACCESS_KEY')

      @region = @config['region']
      @bucket_name = @config['bucket_name']
      @endpoint = @config['endpoint']

      @s3_resource = nil
      @bucket = nil
    end

    def html_url; end

    # As of now, the exception handling only logs the errors without any additional recovery or fallback mechanisms.
    # Future enhancements may include more robust error handling strategies.
    def handle_exceptions(where)
      yield
    rescue Aws::Errors::ServiceError => e
      @logger.error("S3Compatible Error in #{where}: #{e.message}")
      false
    rescue StandardError => e
      @logger.error("S3Compatible General error in #{where}: #{e.message}")
      false
    end

    # This method is intentionally left blank to maintain the interface,
    # as S3-compatible does not require this function. It prevents external calls
    # from causing errors while adhering to the expected API structure.
    def ask_token; end

    def connect
      handle_exceptions(__method__) do
        @s3_resource = Aws::S3::Resource.new(
          access_key_id: @access_key_id,
          secret_access_key: @secret_access_key,
          region: @region, endpoint: "https://#{@endpoint}",
          force_path_style: true # Necessary for compatibility with S3-compatible services
          # such as Alibaba Cloud OSS, which do not support virtual-hosted style.
          # Forces path-style access to ensure proper functionality.
        )
        @bucket = @s3_resource.bucket(@bucket_name)
        @logger.info("S3Compatible bucket connected: #{@bucket_name}")
        true
      end
    end

    def create_project_folder
      handle_exceptions(__method__) do
        @path = "#{@repo}/CI/#{@tag}-#{@timestamp}"
        update_index_file
        @url = generate_url("#{@path}/#{INDEX_FILE_NAME}")
        @logger.info("S3Compatible project folder created: #{@url}")
        true
      end
    end

    def upload_file(l_path, r_name)
      handle_exceptions(__method__) do
        remote_path = "#{@path}/#{r_name}"
        type = 'text/html' if r_name.end_with?('.html')
        obj = @bucket.object(remote_path)
        obj.upload_file(l_path, content_type: type)
        update_index_file
        @logger.info("S3Compatible file uploaded: #{remote_path}")
        true
      end
    end

    def update_file_content(content, r_name)
      handle_exceptions(__method__) do
        remote_path = "#{@path}/#{r_name}"
        obj = @bucket.object(remote_path)
        obj.put(body: content)
        @logger.info("S3Compatible file content updated: #{remote_path}")
        true
      end
    end

    def delete_file(r_name)
      handle_exceptions(__method__) do
        r_path = "#{@path}/#{r_name}"
        obj = @bucket.object(r_path)
        obj.delete
        update_index_file
        @logger.info("S3Compatible file deleted: #{r_path}")
        true
      end
    end

    def close; end

    private

    def update_index_file
      title = @path.split('/').last
      html_content = build_html_content(title)
      html_content += list_objects
      save_index_file(html_content)
    end

    def build_html_content(title)
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>#{title}</title>
            <style>
                body {
                    font-family: Arial, sans-serif;
                }
                h1 {
                    color: #333;
                }
                ul {
                    list-style-type: none;
                    padding: 0;
                }
                li {
                    margin: 5px 0;
                }
                a {
                    text-decoration: none;
                    color: #007bff;
                }
                a:hover {
                    text-decoration: underline;
                }
            </style>
        </head>
        <body>
            <h1>#{title}</h1>
            <ul>
      HTML
    end

    def list_objects
      objects_html = ''
      objects = @bucket.objects(prefix: @path)

      objects.each do |object|
        file_name = object.key.split('/').last
        next if file_name == INDEX_FILE_NAME

        file_url = generate_url(object.key)
        objects_html += "<li><a href=\"#{file_url}\">#{file_name}</a></li>\n"
      end

      "#{objects_html}</ul>\n</body>\n</html>\n"
    end

    def save_index_file(html_content)
      obj = @bucket.object("#{@path}/#{INDEX_FILE_NAME}")
      obj.put(body: html_content, content_type: 'text/html')
    end

    # @note It is required that the bucket has public read permissions set.
    # This ensures that the generated URL will be accessible without authentication.
    def generate_url(object)
      "https://#{@bucket_name}.#{@endpoint}/#{object}"
    end
  end
end
