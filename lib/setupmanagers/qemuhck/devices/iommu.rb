# typed: true
# frozen_string_literal: true

require 'sys/cpu'

module AutoHCK
  class IommuDevice
    extend T::Sig

    def initialize(logger)
      @logger = logger
    end

    sig { returns(Models::QemuHCKDevice) }
    def qemu_hck_device
      vendor = Sys::CPU.processors[0].vendor_id

      case vendor
      when 'GenuineIntel'
        Models::QemuHCKDevice.from_json_file("#{__dir__}/intel-iommu.json", @logger)
      when 'AuthenticAMD'
        Models::QemuHCKDevice.from_json_file("#{__dir__}/amd-iommu.json", @logger)
      else
        @logger.fatal('Unknown CPU vendor')
        exit 1
      end
    end
  end
end
