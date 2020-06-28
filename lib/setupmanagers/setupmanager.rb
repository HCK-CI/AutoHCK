# frozen_string_literal: true

require './lib/exceptions'
require './lib/setupmanagers/virthck/virthck'
require './lib/setupmanagers/physhck/physhck'

# SetupManager
#
class SetupManager
  attr_reader :id
  # SetupManagerFactory
  #
  class SetupManagerFactory
    SETUP_MANAGERS = {
      virthck: VirtHCK,
      physhck: PhysHCK
    }.freeze

    def self.create(type, project)
      SETUP_MANAGERS[type].new(project)
    end

    def self.can_create?(type)
      !SETUP_MANAGERS[type].nil?
    end
  end

  def initialize(project)
    @project = project
    @logger = project.logger
    @type = project.setupmanager.downcase.to_sym
    setupmanager_create
  end

  def setupmanager_create
    if SetupManagerFactory.can_create?(@type)
      @setupmanager = SetupManagerFactory.create(@type, @project)
    else
      @logger.warn("Unkown type setup mainager #{@type}, Exiting...")
      raise SetupManagerError, "Unkown type setup manager #{@type}"
    end
  end

  def create_studio_snapshot
    @setupmanager.create_studio_snapshot
  end

  def delete_studio_snapshot
    @setupmanager.delete_studio_snapshot
  end

  def create_client_snapshot(name)
    @setupmanager.create_client_snapshot(name)
  end

  def delete_client_snapshot(name)
    @setupmanager.delete_client_snapshot(name)
  end

  def run(name, first_time = false)
    @setupmanager.run(name, first_time)
  end

  def create_studio
    @setupmanager.create_studio
  end

  def create_client(tag, name)
    @setupmanager.create_client(tag, name)
  end

  def close
    @setupmanager.close
  end
end
