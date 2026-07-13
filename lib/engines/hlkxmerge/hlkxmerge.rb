# typed: true
# frozen_string_literal: true

module AutoHCK
  # HLKXMerge engine: merges multiple HLKX packages into one using the HLK API
  # running on a Studio VM. No HLK clients or test execution are needed.
  #
  # Usage:
  #   auto_hck merge --platform <platform> --packages a.hlkx,b.hlkx --output merged.hlkx
  class HLKXMerge
    extend T::Sig
    include Helper

    ENGINE_MODE = 'merge'
    PLATFORMS_JSON_DIR = 'lib/engines/hcktest/platforms'

    def initialize(project)
      @project = project
      @logger = project.logger
      @project.append_multilog('hlkxmerge.log')
    end

    def self.tag(options)
      "merge-#{options.merge.platform}"
    end

    sig { params(logger: MultiLogger, options: CLI).returns(Models::HLKPlatform) }
    def self.platform(logger, options)
      platform_name = options.merge.platform
      raise AutoHCKError, 'Missing required option: --platform' if platform_name.nil?

      Models::HLKPlatform.from_json_file(
        "#{PLATFORMS_JSON_DIR}/#{platform_name}.json",
        logger
      )
    end

    def result_uploader_needed?
      false
    end

    def drivers
      []
    end

    def test_steps
      []
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def clients_system_info
      {}
    end

    def run
      validate_options

      ResourceScope.open do |scope|
        boot_and_connect_studio(scope)
        run_merge
      end
    end

    private

    def validate_options
      packages = @project.options.merge.packages

      raise AutoHCKError, 'At least 2 packages are required for merge' if packages.size < 2

      packages.each do |pkg|
        raise InvalidPathError, "Package file not found: #{pkg}" unless File.exist?(pkg)
      end
    end

    def boot_and_connect_studio(scope)
      @studio = @project.setup_manager.run_hck_studio(scope, {})
      @logger.info('Waiting for Studio to load...')
      sleep 5 until @studio.up?
      @studio.connect
      @studio.verify_tools
      @logger.info('Studio connected')
    end

    def upload_packages
      @project.options.merge.packages.map.with_index do |local_path, i|
        filename = File.basename(local_path)
        remote_path = "C:\\AutoHCK\\merge_input_#{i}_#{filename}"
        @logger.info("Uploading #{filename} to Studio...")
        @studio.tools.upload_to_studio(local_path, remote_path)
        remote_path
      end
    end

    def print_merge_results(result)
      messages = (result['messages'] || []).map { "    -- #{_1}\n" }.join
      if result['iserror'] == false
        @logger.info('Merge completed successfully')
        @logger.debug("Merge result:\n#{messages}")
      else
        @logger.warn('Merge got an error. Check the logs for details.')
        @logger.warn("Merge result:\n#{messages}")
      end
    end

    def run_merge
      remote_packages = upload_packages

      @logger.info("Merging #{remote_packages.size} packages...")
      result = @studio.tools.merge_hlkx_packages(remote_packages)
      raise AutoHCKError, 'Merge failed: invalid response from Studio tools' unless result.is_a?(Hash)

      print_merge_results(result)
      raise AutoHCKError, 'Merge failed: Studio tools reported an error' unless result['iserror'] == false

      downloaded_path = result['hostprojectpackagepath']
      raise AutoHCKError, 'Merge failed: merged package path not found' unless downloaded_path

      save_output(downloaded_path)
    end

    def save_output(downloaded_path)
      output_file = @project.options.merge.output_file
      if output_file && downloaded_path != output_file
        FileUtils.mkdir_p(File.dirname(output_file))
        FileUtils.mv(downloaded_path, output_file)
        @logger.info("Merge complete. Output: #{output_file}")
      else
        @logger.info("Merge complete. Output: #{downloaded_path}")
      end
    rescue SystemCallError => e
      raise AutoHCKError, "Failed to save merged package to #{output_file}: #{e.message}"
    end
  end
end
