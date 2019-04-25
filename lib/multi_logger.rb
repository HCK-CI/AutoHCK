# MultiLogger class
class MultiLogger
  attr_reader :level

  def initialize(*loggers)
    @level = Logger::Severity::DEBUG
    @loggers = []

    loggers.each { |logger| add_logger(logger) }
  end

  def remove_logger(logger)
    @loggers.delete(logger)
  end

  def add_logger(logger)
    logger.level = level
    @loggers << logger
  end

  def level=(level)
    @level = level
    @loggers.each { |logger| logger.level = level }
  end

  def close
    @loggers.map(&:close)
  end

  Logger::Severity.constants.each do |level|
    define_method(level.downcase) do |*args|
      @loggers.each { |logger| logger.send(level.downcase, *args) }
    end

    define_method("#{level.downcase}?".to_sym) do
      @level <= Logger::Severity.const_get(level)
    end
  end
end
