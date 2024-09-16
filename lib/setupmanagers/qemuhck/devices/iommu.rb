# typed: true
# frozen_string_literal: true

module AutoHCK
  class QemuHCK
    module Devices
      extend T::Sig

      sig { params(logger: AutoHCK::MultiLogger).returns(Models::QemuHCKDevice) }
      def self.iommu(logger)
        cpuinfo = File.read('/proc/cpuinfo')
        vendor_match = cpuinfo.match(/^vendor_id\s*:\s*(\S+)/)

        raise QemuHCKError, 'Could not determine CPU vendor' if vendor_match.nil?

        vendor = vendor_match[1]

        case vendor
        when 'GenuineIntel'
          Models::QemuHCKDevice.from_json_file("#{__dir__}/intel-iommu.json", logger)
        when 'AuthenticAMD'
          Models::QemuHCKDevice.from_json_file("#{__dir__}/amd-iommu.json", logger)
        else
          raise QemuHCKError, "Unknown CPU vendor: #{vendor}"
        end
      end
    end
  end
end
