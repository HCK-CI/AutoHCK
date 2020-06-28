# frozen_string_literal: true

require './lib/setupmanagers/setupmanager'
require './lib/setupmanagers/exceptions'
require './lib/setupmanagers/monitor'

# Machine class
class Machine
  attr_reader :name
  def initialize(project, name, setupmanager, id, tag)
    @name = name
    @tag = tag
    @project = project
    @setupmanager = setupmanager
    @logger = project.logger
    @id = id
  end

  def run
    @logger.info("Starting #{@name}")
    @pid = @setupmanager.run(@tag, true)
    raise MachinePidNil, "#{@name} PID could not be retrieved" unless @pid

    return if @pid.negative?

    @logger.info("#{@name} PID is #{@pid}")
    @monitor = Monitor.new(@project, self)
    raise MachineRunError, "Could not start #{@name}" unless alive?
  rescue CmdRunError
    raise MachineRunError, "Could not start #{@name}"
  end

  def hard_abort
    @monitor&.quit
    sleep ABORT_SLEEP
    return true unless alive?

    false
  end

  def clean_last_run
    return if @pid.negative?

    @logger.info("Cleaning last #{@name} run")
    unless hard_abort
      @logger.info("#{@name} hard abort failed, force aborting...")
      Process.kill('KILL', @pid)
    end
    delete_snapshot
  end

  def powerdown
    return if @pid.negative?

    @monitor&.powerdown
  end

  # machine soft abort trials before force abort
  ABORT_RETRIES = 3

  # machine soft abort sleep for each trial
  ABORT_SLEEP = 5

  def soft_abort
    ABORT_RETRIES.times do
      return true unless alive?

      powerdown
      sleep ABORT_SLEEP
    end
    false
  end

  def abort
    return if @pid.negative? || soft_abort

    @logger.info("#{@name} soft abort failed, hard aborting...")
    return if hard_abort

    @logger.info("#{@name} hard abort failed, force aborting...")
    Process.kill('KILL', @pid)
  end

  def alive?
    return false unless @pid
    return true if @pid.negative?

    Process.kill(0, @pid)
    true
  rescue Errno::ESRCH
    @logger.info("#{@name} is not alive")
    false
  end
end
