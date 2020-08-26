# frozen_string_literal: true

require 'yaml'

# selective trigger class
class DiffChecker
  DIFF_FILENAME = 'diff.txt'
  TRIGGER_YAML = 'triggers.yml'

  def initialize(logger, driver, driver_path, diff)
    @logger = logger
    @driver = driver['short']
    @diff = diff || driver_path + '/' + DIFF_FILENAME
  end

  def load_driver_triggers
    @logger.info('Loading diff checker trigger file')
    yaml = YAML.safe_load(File.read(TRIGGER_YAML))
    yaml.select! { |_key, value| value ? value & [@driver, '*'] != [] : false }
    yaml.keys
  end

  def load_diff_files
    @logger.info('Loading driver diff file')
    File.readlines(@diff)
  end

  def root_trigger?(triggers, files)
    triggers.include?('/') && files.any? { |file| !file.include?('/') }
  end

  def subdir_trigger?(triggers, files)
    files.any? { |line| triggers.any? { |trigger| line.start_with?(trigger) } }
  end

  def trigger?
    return true unless File.file?(@diff) && File.file?(TRIGGER_YAML)

    files = load_diff_files
    triggers = load_driver_triggers
    root_trigger?(triggers, files) || subdir_trigger?(triggers, files)
  end
end
