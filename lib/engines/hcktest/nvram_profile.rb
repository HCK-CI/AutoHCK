# frozen_string_literal: true

require 'digest'

module AutoHCK
  class HCKTest
    # Run SVVP tests with temporary SUT firmware settings, then restore the original state.
    class NvramProfile
      KEY_DATABASES = %w[PK KEK db dbx].freeze
      GOP_PROFILE = 'uefi_gop_1024x768'
      SETUP_PROFILE = 'uefi_secure_boot_setup'
      VIRT_FW_VARS = '/usr/bin/virt-fw-vars'
      # Set the firmware display mode without changing other NVRAM variables.
      GOP_VARIABLES = {
        'PlatformConfig' => {
          'name' => 'PlatformConfig', 'guid' => '7235c51c-0c80-4cab-87ac-3b084a6304b1',
          'attr' => 7, 'data' => '0004000000030000'
        }
      }.freeze
      # Read Secure Boot state and surface guest access errors.
      READ_STATE = <<~'POWERSHELL'
        $ErrorActionPreference = 'Stop'
        $state = @{}
        foreach ($name in @('SetupMode', 'SecureBoot')) {
          $bytes = (Get-SecureBootUEFI -Name $name).Bytes
          if ($bytes.Length -ne 1) { throw "Invalid $name variable" }
          $state[$name] = [int]$bytes[0]
        }
        foreach ($name in @('PK', 'KEK', 'db', 'dbx')) {
          try {
            $state[$name] = [Convert]::ToBase64String((Get-SecureBootUEFI -Name $name).Bytes)
          } catch {
            if ($_.Exception.Message -notmatch 'Variable is currently undefined|0xC0000100') { throw }
            $state[$name] = $null
          }
        }
        $state | ConvertTo-Json -Compress
      POWERSHELL

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
        validate_scope
        raise EngineError, "Unknown NVRAM profile: #{profile}" unless [GOP_PROFILE, SETUP_PROFILE].include?(profile)

        @profile = profile
        raise EngineError, "#{VIRT_FW_VARS} is required for #{profile}" unless File.executable?(VIRT_FW_VARS)

        @original = @manager.client_nvram_path(@client.name)
        @client.wait_for_existing_target(@target)
        verify_idle
        unless gop_profile?
          @baseline = read_state
          verify_enrolled(@baseline)
        end
        prepare_journal(profile)
        begin
          enter_profile
          @client.wait_for_existing_target(@target)
          verify_setup(read_state) unless gop_profile?
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

      def validate_scope
        unless @scope && @project.options.test.svvp && @project.engine_platform.setupmanager == 'qemuhck' &&
               @project.engine.platform_clients.role_for(@client.name) == Models::ClientRole::Sut
          raise EngineError, 'nvram_profile requires an active qemuhck SVVP SUT scope'
        end
      end

      def gop_profile?
        @profile == GOP_PROFILE
      end

      def read_state
        output = @tools.act_with_tools_on_machine(@client.name) do |tools|
          tools.run_on_machine(@client.name, READ_STATE)
        end
        state = JSON.parse(output)
        unless state.is_a?(Hash) && (KEY_DATABASES + %w[SetupMode SecureBoot]).all? { state.key?(_1) }
          raise EngineError, 'Incomplete Secure Boot variable readback'
        end

        state
      end

      def verify_enrolled(state)
        return if state['SetupMode'] == 0 && state['SecureBoot'] == 1 &&
                  %w[PK KEK db].all? { |name| state[name].is_a?(String) && !state[name].empty? }

        raise EngineError, 'Expected enrolled Secure Boot before NVRAM transition; use uefi with secure_boot=true'
      end

      def verify_setup(state)
        return if state['SetupMode'] == 1 && state['SecureBoot'] == 0 &&
                  KEY_DATABASES.all? { |name| state[name].nil? || state[name] == '' }

        raise EngineError, 'Clean NVRAM did not produce SetupMode=1, SecureBoot=0 and empty PK/KEK/db/dbx'
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
        @temporary_inventory = File.join(@workspace, "nvram_#{gop_profile? ? 'gop' : 'setup'}_#{@transition_id}.json")
        @journal.merge!('original_inventory' => @original_inventory, 'temporary_inventory' => @temporary_inventory)
        if gop_profile?
          @settings = File.join(@workspace, "nvram_gop_settings_#{@transition_id}.json")
          @journal['settings'] = @settings
        end
        record('prepared')
      end

      # Record transition progress for recovery after interruptions.
      def record(phase)
        @journal.merge!('phase' => phase, 'time' => Time.now.utc.iso8601)
        staging = "#{@journal_path}.#{SecureRandom.hex(6)}.tmp"
        File.open(staging, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          file.write(JSON.pretty_generate(@journal))
          file.flush
          file.fsync
        end
        File.rename(staging, @journal_path)
        @logger.info("NVRAM transition #{@client.name}: #{phase}; journal: #{@journal_path}")
      ensure
        begin
          File.unlink(staging) if staging && File.exist?(staging)
        rescue StandardError => e
          @logger.warn("Could not remove incomplete NVRAM journal staging file #{staging}: #{e.message}")
        end
      end

      def enter_profile
        @manager.stop_client(@client.name)
        @journal['original_sha256'] = Digest::SHA256.file(@original).hexdigest
        if gop_profile?
          prepare_gop_nvram
        else
          prepare_setup_nvram
        end
        record('switching_to_profile')
        @manager.restart_client_with_nvram(@scope, @client.name, @temporary)
        record('profile_active')
      end

      # Clear Secure Boot keys in a copy of the SUT's current NVRAM.
      def prepare_setup_nvram
        run_virt_fw_vars('--input', @original, '--output-json', @original_inventory)
        original = nvram_inventory(@original_inventory)
        unless %w[PK KEK db].all? { |name| original.key?(name) }
          raise EngineError, 'Enrolled NVRAM is missing PK, KEK or db'
        end

        arguments = KEY_DATABASES.flat_map { |name| ['--delete', name] }
        run_virt_fw_vars('--input', @original, *arguments, '--output', @temporary)
        unless File.file?(@temporary) && File.size(@temporary) == File.size(@original)
          raise EngineError, 'Setup Mode NVRAM copy is missing or has an incompatible size'
        end

        run_virt_fw_vars('--input', @temporary, '--output-json', @temporary_inventory)
        edited = nvram_inventory(@temporary_inventory)
        expected = original.reject { |name, _variable| KEY_DATABASES.include?(name) }
        unless matching_nvram_inventory?(expected, edited)
          raise EngineError, 'Setup Mode NVRAM readback differs beyond PK/KEK/db/dbx'
        end

        verify_original_nvram_unchanged
        @logger.info("Setup Mode NVRAM prepared from #{@original} at #{@temporary}; PK/KEK/db/dbx absent")
      end

      # Prepare a temporary 1024x768 NVRAM copy for the GOP test.
      def prepare_gop_nvram
        run_virt_fw_vars('--input', @original, '--output-json', @original_inventory)
        original = nvram_inventory(@original_inventory)
        validate_original_gop_variables(original)

        settings = { 'version' => 2, 'variables' => [GOP_VARIABLES.fetch('PlatformConfig')] }
        File.open(@settings, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          file.write(JSON.pretty_generate(settings))
        end
        run_virt_fw_vars('--input', @original, '--set-json', @settings, '--output', @temporary)
        unless File.file?(@temporary) && File.size(@temporary) == File.size(@original)
          raise EngineError, 'GOP NVRAM copy is missing or has an incompatible size'
        end

        run_virt_fw_vars('--input', @temporary, '--output-json', @temporary_inventory)
        edited = nvram_inventory(@temporary_inventory)
        expected = original.merge(GOP_VARIABLES)
        unless matching_nvram_inventory?(expected, edited)
          raise EngineError, 'GOP NVRAM readback differs beyond PlatformConfig'
        end

        verify_original_nvram_unchanged

        @logger.info("GOP NVRAM prepared from #{@original} at #{@temporary}; 1024x768")
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
        if platform_config && platform_config.fetch('data').size != 16
          raise EngineError, 'Unexpected PlatformConfig size in original NVRAM'
        end
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

      # Preserve serial evidence before the original firmware boots again.
      def archive_serial
        index = @project.engine_platform.clients.values.index { _1.name == @client.name }
        prefix = format('%04d_%02d', @project.id.to_i, index + 1)
        source = File.join(@workspace, "uefi_serial_#{prefix}.log")
        return unless File.file?(source)

        destination = File.join(@workspace, "uefi_serial_#{prefix}_#{@transition_id}_profile.log")
        FileUtils.cp(source, destination)
        @logger.info("Preserved profile serial output: #{destination}")
      rescue StandardError => e
        @logger.error("Could not preserve profile serial output: #{e.message}")
      end

      def restore(cleanup)
        restore_nvram
        cleanup_after_restore(cleanup)
        complete_transition
      end

      # Return the SUT to its original firmware state.
      def restore_nvram
        @manager.stop_client(@client.name)
        archive_serial
        original_hash = @journal['original_sha256']
        if original_hash && Digest::SHA256.file(@original).hexdigest != original_hash
          raise EngineError, 'Saved normal NVRAM changed while the profile was active; refusing to boot it'
        end

        begin
          record('restoring')
        rescue StandardError => e
          # Continue recovery when a journal update fails.
          @logger.warn("Could not update NVRAM restoration journal; continuing restoration: #{e.class}: #{e.message}")
        end
        @manager.select_client_nvram(@client.name, @original)
        # Require an idle HLK target before returning to normal firmware.
        verify_idle
        @manager.restart_client_with_nvram(@scope, @client.name, @original)
        @client.wait_for_existing_target(@target)
        unless gop_profile?
          restored = read_state
          verify_enrolled(restored)
          raise EngineError, 'Restored Secure Boot databases differ from the pre-test values' unless restored == @baseline
        end
      rescue StandardError => e
        stop_after_transition_failure('NVRAM restoration failed', e)
        raise
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
        if gop_profile?
          @logger.info("Original NVRAM restored on #{@client.name}; HLK target verified")
        else
          @logger.info("Normal NVRAM restored on #{@client.name}; SecureBoot=1, original keys and HLK target verified")
        end
      rescue StandardError => e
        stop_after_transition_failure('Normal NVRAM restored and verified, but transition journal completion failed', e)
        raise
      end

      def stop_after_transition_failure(context, error)
        @logger.error("#{context}: #{error.class}: #{error.message}; stopping #{@client.name}. Inspect #{@journal_path}")
        @manager.stop_client(@client.name)
      rescue StandardError => stop_error
        @logger.error("Could not stop #{@client.name} after transition failure: #{stop_error.class}: #{stop_error.message}")
      end
    end
  end
end
