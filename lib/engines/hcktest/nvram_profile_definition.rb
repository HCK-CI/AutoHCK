# frozen_string_literal: true

module AutoHCK
  class HCKTest
    # Define the firmware changes and checks required by each NVRAM profile.
    class NvramProfileDefinition
      SECURE_BOOT_DATABASES = %w[PK KEK db dbx].freeze
      GUEST_STATE_KEYS = (SECURE_BOOT_DATABASES + %w[SetupMode SecureBoot]).freeze
      # Read Secure Boot state and surface guest access errors.
      READ_SECURE_BOOT_STATE = <<~POWERSHELL
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
      # Set the firmware display mode without changing other NVRAM variables.
      # PlatformConfig uses OVMF's gOvmfPlatformConfigGuid. Attributes 7 enable
      # non-volatile, boot-service, and runtime access. The data stores width
      # (1024) and height (768) as little-endian 32-bit integers.
      GOP_VARIABLES = {
        'PlatformConfig' => {
          'name' => 'PlatformConfig', 'guid' => '7235c51c-0c80-4cab-87ac-3b084a6304b1',
          'attr' => 7, 'data' => '0004000000030000'
        }.freeze
      }.freeze
      ATTRIBUTES = %i[kind label changed_variables prepared_detail restored_message variables delete_variables devices
                      guest_state_command].freeze

      attr_reader :variables, :delete_variables, :devices, :kind, :label, :changed_variables, :prepared_detail,
                  :guest_state_command

      def initialize(**attributes)
        validate_attributes!(attributes)
        @kind = attributes.fetch(:kind)
        @label = attributes.fetch(:label)
        @changed_variables = attributes.fetch(:changed_variables)
        @prepared_detail = attributes.fetch(:prepared_detail)
        @restored_message = attributes.fetch(:restored_message)
        @variables = attributes.fetch(:variables, {}).freeze
        @delete_variables = attributes.fetch(:delete_variables, []).freeze
        @devices = attributes.fetch(:devices, []).freeze
        @guest_state_command = attributes[:guest_state_command]
        freeze
      end

      def validate_attributes!(attributes)
        unknown = attributes.keys - ATTRIBUTES
        raise ArgumentError, "unknown keywords: #{unknown.join(', ')}" unless unknown.empty?
      end

      def verify_guest_state?
        !@guest_state_command.nil?
      end

      def restored_message(client_name)
        format(@restored_message, client: client_name)
      end

      def settings?
        !@variables.empty?
      end

      def settings_document
        { 'version' => 2, 'variables' => @variables.values }
      end

      def edit_arguments(settings_path)
        arguments = @delete_variables.flat_map { |name| ['--delete', name] }
        arguments.push('--set-json', settings_path) if settings?
        arguments
      end

      def expected_inventory(original)
        original.except(*@delete_variables).merge(@variables)
      end

      # Check that the current NVRAM can safely be edited for this profile.
      def validate_original_inventory!(original)
        validate_enrolled_keys!(original) if verify_guest_state?
        validate_configured_variables!(original)
      end

      def validate_enrolled_keys!(original)
        return if %w[PK KEK db].all? { |name| original.key?(name) }

        raise EngineError, 'Enrolled NVRAM is missing PK, KEK or db'
      end

      def validate_configured_variables!(original)
        @variables.each do |name, expected|
          variable = original[name]
          next unless variable
          unless %w[guid attr].all? { |field| variable[field].to_s.downcase == expected[field].to_s.downcase }
            raise EngineError, "Unexpected #{name} GUID or attributes in original NVRAM"
          end
        end

        validate_platform_config_size!(original) if @variables.key?('PlatformConfig')
      end

      def validate_platform_config_size!(original)
        platform_config = original['PlatformConfig']
        return unless platform_config && platform_config.fetch('data').size != 16

        raise EngineError, 'Unexpected PlatformConfig size in original NVRAM'
      end

      def matching_inventory?(expected, edited)
        return false unless expected.keys.sort == edited.keys.sort

        expected.all? do |name, value|
          %w[guid attr data].all? do |field|
            value[field].to_s.downcase == edited.dig(name, field).to_s.downcase
          end
        end
      end

      def validate_guest_readback!(state)
        return if state.is_a?(Hash) && GUEST_STATE_KEYS.all? { state.key?(_1) }

        raise EngineError, 'Incomplete Secure Boot variable readback'
      end

      def validate_baseline!(state)
        return if state['SetupMode']&.zero? && state['SecureBoot'] == 1 &&
                  %w[PK KEK db].all? { |name| state[name].is_a?(String) && !state[name].empty? }

        raise EngineError, 'Expected enrolled Secure Boot before NVRAM transition; use uefi with secure_boot=true'
      end

      def validate_active_guest_state!(state)
        return if state['SetupMode'] == 1 && state['SecureBoot']&.zero? &&
                  @delete_variables.all? { |name| state[name].nil? || state[name] == '' }

        raise EngineError, 'Clean NVRAM did not produce SetupMode=1, SecureBoot=0 and empty PK/KEK/db/dbx'
      end

      def validate_restored_guest_state!(baseline, restored)
        validate_baseline!(restored)
        return if restored == baseline

        raise EngineError, 'Restored Secure Boot databases differ from the pre-test values'
      end

      PROFILES = {
        'uefi_gop_1024x768' => new(
          kind: :gop,
          label: 'GOP',
          changed_variables: 'PlatformConfig',
          prepared_detail: '1024x768',
          restored_message: 'Original NVRAM restored on %<client>s; HLK target verified',
          variables: GOP_VARIABLES
        ),
        'uefi_secure_boot_setup' => new(
          kind: :setup,
          label: 'Setup Mode',
          changed_variables: 'PK/KEK/db/dbx',
          prepared_detail: 'PK/KEK/db/dbx absent',
          restored_message: 'Normal NVRAM restored on %<client>s; ' \
                            'SecureBoot=1, original keys and HLK target verified',
          delete_variables: SECURE_BOOT_DATABASES,
          devices: ['usb-storage-dual'],
          guest_state_command: READ_SECURE_BOOT_STATE
        )
      }.freeze

      def self.fetch(name)
        PROFILES.fetch(name) { raise EngineError, "Unknown NVRAM profile: #{name}" }
      end
    end
  end
end
