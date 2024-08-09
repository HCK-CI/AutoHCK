# frozen_string_literal: true

module AutoHCK
  module Models
    extend AutoloadExtension

    autoload_relative :CommandInfo, 'models/command_info'
    autoload_relative :DriverInstallMethods, 'models/driver_install_methods'
    autoload_relative :Driver, 'models/driver'
    autoload_relative :HCKTestConfig, 'models/hcktest_config'
    autoload_relative :JsonHelper, 'models/json_helper'
    autoload_relative :SVVPConfig, 'models/svvp_config'
    autoload_relative :QemuHCKDevice, 'models/qemuhck_device'
  end
end
