# frozen_string_literal: true

module AutoHCK
  class HCKTest
    # Define the firmware changes and checks required by each NVRAM profile.
    class NvramProfileDefinition
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

      attr_reader :variables, :delete_variables, :kind, :label, :changed_variables, :prepared_detail

      def initialize(kind:, label:, changed_variables:, prepared_detail:, restored_message:, variables: {})
        @kind = kind
        @label = label
        @changed_variables = changed_variables
        @prepared_detail = prepared_detail
        @restored_message = restored_message
        @variables = variables.freeze
        @delete_variables = [].freeze
        freeze
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
        arguments.concat(['--set-json', settings_path]) if settings?
        arguments
      end

      def expected_inventory(original)
        original.except(*@delete_variables).merge(@variables)
      end

      # Check that the current NVRAM can safely be edited for this profile.
      def validate_original_inventory!(original)
        @variables.each do |name, expected|
          variable = original[name]
          next unless variable
          unless %w[guid attr].all? { |field| variable[field].to_s.downcase == expected[field].to_s.downcase }
            raise EngineError, "Unexpected #{name} GUID or attributes in original NVRAM"
          end
        end
        platform_config = original['PlatformConfig'] if @variables.key?('PlatformConfig')
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

      PROFILES = {
        'uefi_gop_1024x768' => new(kind: :gop, label: 'GOP', changed_variables: 'PlatformConfig',
                                  prepared_detail: '1024x768',
                                  restored_message: 'Original NVRAM restored on %<client>s; HLK target verified',
                                  variables: GOP_VARIABLES)
      }.freeze

      def self.fetch(name)
        PROFILES.fetch(name) { raise EngineError, "Unknown NVRAM profile: #{name}" }
      end
    end
  end
end
