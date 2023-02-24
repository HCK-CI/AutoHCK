# frozen_string_literal: true

require 'yaml'

# AutoHCK module
module AutoHCK
  # selective trigger class
  class DiffChecker
    DIFF_FILENAME = 'diff.txt'
    TRIGGER_YAML = 'triggers.yml'

    def initialize(logger, drivers_name, driver_path, diff = nil, triggers = nil)
      @logger = logger
      @drivers_name = drivers_name
      @diff = diff || "#{driver_path}/#{DIFF_FILENAME}"
      @triggers = triggers || TRIGGER_YAML
    end

    def load_drivers_triggers
      @logger&.info('Loading diff checker trigger file')
      yaml = YAML.safe_load(File.read(@triggers))

      @trigger_includes = []
      @trigger_excludes = []

      yaml.each do |key, value|
        if [*@drivers_name, '*'].include?(key)
          @trigger_includes << value['include']
          @trigger_excludes << value['exclude']
        end
      end

      normalize_lists

      @logger&.debug("Loaded trigger includes: #{@trigger_includes}")
      @logger&.debug("Loaded trigger excludes: #{@trigger_excludes}")
    end

    def normalize_lists
      @trigger_includes.flatten!
      @trigger_includes.compact!
      @trigger_includes.uniq!

      @trigger_excludes.flatten!
      @trigger_excludes.compact!
      @trigger_excludes.uniq!
    end

    def check_trigger_file(trigger, line)
      if trigger[-1] == '/'
        # trigger is a directory
        # applying for all files
        line.start_with?(trigger)
      else
        # trigger is a file
        line == trigger
      end
    end

    def load_diff_files
      @logger&.info('Loading driver diff file')

      @files = File.readlines(@diff, chomp: true)
      @logger&.debug("Loaded driver diff files: #{@files}")

      @files_no_excludes = @files.reject do |line|
        @trigger_excludes.any? do |trigger|
          check_trigger_file(trigger, line)
        end
      end
      @logger&.debug("Driver diff files w/o excludes: #{@files_no_excludes}")
    end

    def root_trigger?
      @logger&.debug('Processing root triggers')

      return false unless @trigger_includes.include?('/')

      @files_no_excludes.any? { |file| !file.include?('/') }
    end

    def subdir_trigger?
      @files_no_excludes.any? do |line|
        @trigger_includes.any? do |trigger|
          check_trigger_file(trigger, line)
        end
      end
    end

    def trigger?
      return true unless File.file?(@diff) && File.file?(@triggers)

      load_drivers_triggers
      load_diff_files

      root_tr = root_trigger?
      sub_tr = subdir_trigger?
      @logger&.debug("Triggers results: root_trigger? = #{root_tr}, subdir_trigger? = #{sub_tr}")

      root_tr || sub_tr
    end
  end
end
