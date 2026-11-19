# frozen_string_literal: true

module AutoHCK
  module Functest
    # TestContext holds runtime state for test execution
    class TestContext
      attr_reader :logger, :project, :replacement_map

      def initialize(project, replacement_map)
        @project = project
        @logger = project.logger
        @replacement_map = ReplacementMap.new(replacement_map)
        # Baseline of engine-level variables every test starts from; locked by
        # lock_baseline! once run-level setup (setup_test_context, test
        # params) is done. Nil until then, which disables per-test resets.
        @baseline_map = nil
        @test_local_variables = Set.new
        @replacement_map.each { |placeholder, value| @logger.debug("Initial variable '#{placeholder}' = '#{value}'") }
        @start_time = Time.now
      end

      # Store a captured output variable
      def set_variable(name, value)
        @logger.debug("Setting variable '#{name}' = '#{value}'")
        @test_local_variables << name
        @replacement_map.merge!({ "@#{name}@" => value.to_s })
      end

      # Freeze the current variables as the baseline every test starts from.
      # Called when test execution begins, after all engine-level setup
      # (client replacement maps, setup_test_context, test params) has run.
      def lock_baseline!
        @baseline_map = ReplacementMap.new(@replacement_map)
        @test_local_variables.clear
        @logger.debug('Variable baseline locked')
      end

      # Drop variables set or captured by earlier tests, restoring the
      # engine-level baseline. Without this, one test's variables leak into
      # every later test: step substitution applies the full shared map, so a
      # placeholder a later test never declared gets replaced with the stale
      # value (e.g. multi_disk_static's disk_count=23 substituting
      # wait_hotplug_disk.ps1's @disk_count@, which is meant to stay
      # unsubstituted and default to 1, making every later single-disk
      # hotplug test wait for 23 disks and time out).
      #
      # No-op unless lock_baseline! was called, so an executor that never
      # locks keeps the previous (shared) behaviour.
      def reset_test_variables!
        return if @baseline_map.nil? || @test_local_variables.empty?

        dropped = @test_local_variables.sort.join(', ')
        @logger.debug("Dropping variables from previous test: #{dropped}")
        @replacement_map = ReplacementMap.new(@baseline_map)
        @test_local_variables.clear
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
