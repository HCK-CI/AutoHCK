# frozen_string_literal: true

module AutoHCK
  class HCKTest
    # Define the firmware changes and checks required by each NVRAM profile.
    class NvramProfileDefinition
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
      end

      def matching_inventory?(expected, edited)
        return false unless expected.keys.sort == edited.keys.sort

        expected.all? do |name, value|
          %w[guid attr data].all? do |field|
            value[field].to_s.downcase == edited.dig(name, field).to_s.downcase
          end
        end
      end

      PROFILES = {}.freeze

      def self.fetch(name)
        PROFILES.fetch(name) { raise EngineError, "Unknown NVRAM profile: #{name}" }
      end
    end
  end
end
