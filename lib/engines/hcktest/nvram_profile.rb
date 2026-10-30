# frozen_string_literal: true

require 'digest'

module AutoHCK
  class HCKTest
    # Run SVVP tests with temporary SUT firmware settings, then restore the original state.
    class NvramProfile
      GOP_PROFILE = 'uefi_gop_1024x768'
      VIRT_FW_VARS = '/usr/bin/virt-fw-vars'
      # Set the firmware display mode without changing other NVRAM variables.
      GOP_VARIABLES = {
        'PlatformConfig' => {
          'name' => 'PlatformConfig', 'guid' => '7235c51c-0c80-4cab-87ac-3b084a6304b1',
          'attr' => 7, 'data' => '0004000000030000'
        }
      }.freeze
      def initialize(project:, tools:, client:, target:, scope:)
        @project = project
        @tools = tools
        @client = client
        @target = target
        @scope = scope
        @manager = project.setup_manager
        @logger = project.logger
        @workspace = File.expand_path(project.workspace_path)
      end

      # Apply a test profile and restore the original firmware afterward.
      def run(profile, cleanup:)
        prepare_transition(profile)
        prepare_journal(profile)
        begin
          activate_profile
          @logger.info("NVRAM profile ready on #{@client.name}: #{profile}; queuing test")
          @cleanup_pending = true
          yield
        ensure
          # Restore normal firmware after test execution.
          Thread.handle_interrupt(AutoHCKInterrupt => :never) do
            cleanup_before_restore(cleanup)
            restore(cleanup)
          end
        end
      end

      def prepare_transition(profile)
        validate_scope
        raise EngineError, "Unknown NVRAM profile: #{profile}" unless profile == GOP_PROFILE

        raise EngineError, "#{VIRT_FW_VARS} is required for #{profile}" unless File.executable?(VIRT_FW_VARS)

        @original = @manager.client_nvram_path(@client.name)
        @client.wait_for_existing_target(@target)
        verify_idle
      end

      def activate_profile
        enter_profile
        @client.wait_for_existing_target(@target)
      end

      def validate_scope
        unless @scope && @project.options.test.svvp && @project.engine_platform.setupmanager == 'qemuhck' &&
               @project.engine.platform_clients.role_for(@client.name) == Models::ClientRole::Sut
          raise EngineError, 'nvram_profile requires an active qemuhck SVVP SUT scope'
        end
      end

      def verify_idle
        tag = @project.engine_tag
        tests = @tools.act_with_tools { _1.list_tests(@target.fetch('key'), tag, @client.name, tag) }
        return if tests.all? { _1['executionstate'] == 'NotRunning' }

        raise EngineError, 'HLK still has queued/running tests; cancel or finish them before booting normal NVRAM'
      end

      def prepare_journal(profile)
        @transition_id = SecureRandom.hex(8)
        @temporary = File.join(@workspace, "nvram_profile_#{@transition_id}.nvram")
        @journal_path = File.join(@workspace, "nvram_transition_#{@transition_id}.pending.json")
        @journal = {
          'client' => @client.name, 'profile' => profile, 'pool' => @project.engine_tag,
          'target_key' => @target.fetch('key'), 'original' => @original,
          'temporary' => @temporary
        }
        @original_inventory = File.join(@workspace, "nvram_original_#{@transition_id}.json")
        @temporary_inventory = File.join(@workspace, "nvram_gop_#{@transition_id}.json")
        @journal.merge!('original_inventory' => @original_inventory, 'temporary_inventory' => @temporary_inventory)
        @settings = File.join(@workspace, "nvram_gop_settings_#{@transition_id}.json")
        @journal['settings'] = @settings
        record('prepared')
      end

      # Record transition progress for recovery after interruptions.
      def record(phase)
        @journal.merge!('phase' => phase, 'time' => Time.now.utc.iso8601)
        staging = "#{@journal_path}.#{SecureRandom.hex(6)}.tmp"
        write_journal_staging(staging)
        File.rename(staging, @journal_path)
        @logger.info("NVRAM transition #{@client.name}: #{phase}; journal: #{@journal_path}")
      ensure
        remove_journal_staging(staging)
      end

      def write_journal_staging(staging)
        File.open(staging, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          file.write(JSON.pretty_generate(@journal))
          file.flush
          file.fsync
        end
      end

      def remove_journal_staging(staging)
        File.unlink(staging) if staging && File.exist?(staging)
      rescue StandardError => e
        @logger.warn("Could not remove incomplete NVRAM journal staging file #{staging}: #{e.message}")
      end

      def enter_profile
        @manager.stop_client(@client.name)
        @journal['original_sha256'] = Digest::SHA256.file(@original).hexdigest
        prepare_gop_nvram
        record('switching_to_profile')
        @manager.restart_client_with_nvram(@scope, @client.name, @temporary)
        record('profile_active')
      end

      # Prepare a temporary 1024x768 NVRAM copy for the GOP test.
      def prepare_gop_nvram
        original = original_inventory
        validate_original_gop_variables(original)
        write_gop_settings
        run_virt_fw_vars('--input', @original, '--set-json', @settings, '--output', @temporary)
        verify_profile_copy(original.merge(GOP_VARIABLES), 'GOP', 'PlatformConfig')
        @logger.info("GOP NVRAM prepared from #{@original} at #{@temporary}; 1024x768")
      end

      def original_inventory
        run_virt_fw_vars('--input', @original, '--output-json', @original_inventory)
        nvram_inventory(@original_inventory)
      end

      def write_gop_settings
        settings = { 'version' => 2, 'variables' => [GOP_VARIABLES.fetch('PlatformConfig')] }
        File.open(@settings, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          file.write(JSON.pretty_generate(settings))
        end
      end

      def verify_profile_copy(expected, profile, changed_variables)
        unless File.file?(@temporary) && File.size(@temporary) == File.size(@original)
          raise EngineError, "#{profile} NVRAM copy is missing or has an incompatible size"
        end

        run_virt_fw_vars('--input', @temporary, '--output-json', @temporary_inventory)
        edited = nvram_inventory(@temporary_inventory)
        unless matching_nvram_inventory?(expected, edited)
          raise EngineError, "#{profile} NVRAM readback differs beyond #{changed_variables}"
        end

        verify_original_nvram_unchanged
      end

      def verify_original_nvram_unchanged
        return if Digest::SHA256.file(@original).hexdigest == @journal.fetch('original_sha256')

        raise EngineError, 'Original NVRAM changed while preparing the profile copy'
      end

      # Confirm the temporary profile changes only its intended variables.
      def matching_nvram_inventory?(expected, edited)
        return false unless expected.keys.sort == edited.keys.sort

        expected.all? do |name, value|
          %w[guid attr data].all? do |field|
            value[field].to_s.downcase == edited.dig(name, field).to_s.downcase
          end
        end
      end

      # Check that the firmware layout can safely accept GOP settings.
      def validate_original_gop_variables(original)
        GOP_VARIABLES.each do |name, expected|
          variable = original[name]
          next unless variable
          unless %w[guid attr].all? { |field| variable[field].to_s.downcase == expected[field].to_s.downcase }
            raise EngineError, "Unexpected #{name} GUID or attributes in original NVRAM"
          end
        end
        platform_config = original['PlatformConfig']
        return unless platform_config && platform_config.fetch('data').size != 16

        raise EngineError, 'Unexpected PlatformConfig size in original NVRAM'
      end

      def nvram_inventory(path)
        variables = JSON.parse(File.read(path)).fetch('variables')
        raise EngineError, "Invalid NVRAM inventory: #{path}" unless variables.is_a?(Array)

        inventory = variables.to_h { |variable| [variable.fetch('name'), variable] }
        raise EngineError, "Duplicate NVRAM variable names: #{path}" unless inventory.size == variables.size

        inventory
      end

      def run_virt_fw_vars(*arguments)
        ResourceScope.open { CmdRun.new(_1, @logger, VIRT_FW_VARS, *arguments) }
      end

      def cleanup_before_restore(cleanup)
        return unless @cleanup_pending

        cleanup.call
        @cleanup_pending = false
      rescue StandardError => e
        @logger.warn("Profile test cleanup failed; retrying after normal NVRAM boots: #{e.message}")
      end

      def restore(cleanup)
        restore_nvram
        cleanup_after_restore(cleanup)
        complete_transition
      end

      # Return the SUT to its original firmware state.
      def restore_nvram
        @manager.stop_client(@client.name)
        verify_original_nvram_hash
        record_restoring
        # Require an idle HLK target before returning to normal firmware.
        verify_idle
        @manager.restart_client_with_nvram(@scope, @client.name, @original)
        @client.wait_for_existing_target(@target)
      rescue StandardError => e
        stop_after_transition_failure('NVRAM restoration failed', e)
        raise
      end

      def verify_original_nvram_hash
        original_hash = @journal['original_sha256']
        return unless original_hash && Digest::SHA256.file(@original).hexdigest != original_hash

        raise EngineError, 'Saved normal NVRAM changed while the profile was active; refusing to boot it'
      end

      def record_restoring
        record('restoring')
      rescue StandardError => e
        # Continue recovery when a journal update fails.
        @logger.warn("Could not update NVRAM restoration journal; continuing restoration: #{e.class}: #{e.message}")
      end

      # Keep failed guest cleanup from affecting later tests.
      def cleanup_after_restore(cleanup)
        return unless @cleanup_pending

        cleanup.call
        @cleanup_pending = false
      rescue StandardError => e
        stop_after_transition_failure('Normal NVRAM restored and verified, but post-test cleanup failed', e)
        begin
          record('restored_cleanup_failed')
        rescue StandardError => journal_error
          @logger.warn("Could not record cleanup failure: #{journal_error.class}: #{journal_error.message}")
        end
        raise EngineError, "Post-test cleanup failed after normal NVRAM restoration: #{e.class}: #{e.message}"
      end

      def complete_transition
        record('restored_and_verified')
        File.rename(@journal_path, @journal_path.sub('.pending.json', '.completed.json'))
        @logger.info("Original NVRAM restored on #{@client.name}; HLK target verified")
      rescue StandardError => e
        stop_after_transition_failure('Normal NVRAM restored and verified, but transition journal completion failed', e)
        raise
      end

      def stop_after_transition_failure(context, error)
        message = "#{context}: #{error.class}: #{error.message}; stopping #{@client.name}. Inspect #{@journal_path}"
        @logger.error(message)
        @manager.stop_client(@client.name)
      rescue StandardError => e
        @logger.error("Could not stop #{@client.name} after transition failure: #{e.class}: #{e.message}")
      end
    end
  end
end
