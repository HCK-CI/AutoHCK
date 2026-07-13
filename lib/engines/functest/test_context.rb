# frozen_string_literal: true

module AutoHCK
  module Functest
    # TestContext holds runtime state for test execution
    class TestContext
      attr_reader :logger, :project

      def initialize(project, replacement_map)
        @project = project
        @logger = project.logger
        @replacement_map = ReplacementMap.new(replacement_map)
        @replacement_map.each { |placeholder, value| @logger.debug("Initial variable '#{placeholder}' = '#{value}'") }
        @start_time = Time.now
      end

      # Store a captured output variable
      def set_variable(name, value)
        @logger.debug("Setting variable '#{name}' = '#{value}'")
        @replacement_map.merge!({ "@#{name}@" => value.to_s })
      end

      # Substitute variables in a string
      # Example: "ping @SUPPORT_IP@" with variables["SUPPORT_IP"] = "192.168.1.10"
      # Returns: "ping 192.168.1.10"
      def substitute_variables(text, step_variables = {})
        extra = step_variables.each_with_object({}) do |(placeholder, var_name), hash|
          value = @replacement_map["@#{var_name}@"]
          if value.nil?
            @logger.warn("Variable '#{var_name}' not found for placeholder '#{placeholder}'")
          else
            hash[placeholder] = value
          end
        end

        @replacement_map.merge(extra).replace(text)
      end

      def elapsed_time
        Time.now - @start_time
      end
    end
  end
end
