# typed: strict
# frozen_string_literal: true

module AutoHCK
  module Models
    class HLKPlatformClientsOptions < T::Struct
      extend T::Sig
      extend JsonHelper

      prop :viommu_state, T.nilable(T::Boolean)
      prop :enlightenments_state, T.nilable(T::Boolean)
      prop :vbs_state, T.nilable(T::Boolean)
      prop :ctrl_net_device, T.nilable(String)
      prop :fw_type, T.nilable(String)

      # rubocop:disable Metrics/AbcSize
      # There is no way to reduce the ABC size of this method
      sig { params(other: HLKPlatformClientsOptions).void }
      def merge!(other)
        self.viommu_state = other.viommu_state unless other.viommu_state.nil?
        self.enlightenments_state = other.enlightenments_state unless other.enlightenments_state.nil?
        self.vbs_state = other.vbs_state unless other.vbs_state.nil?
        self.ctrl_net_device = other.ctrl_net_device unless other.ctrl_net_device.nil?
        self.fw_type = other.fw_type unless other.fw_type.nil?
      end
      # rubocop:enable Metrics/AbcSize
    end

    class HLKClient < T::Struct
      extend T::Sig
      extend JsonHelper

      const :name, String
      const :cpus, T.nilable(Integer)
      const :memory_gb, T.nilable(Integer)
      const :winrm_addr, T.nilable(String)
      const :winrm_port, T.nilable(Integer)
      const :image, T.nilable(String)
      const :client_iso, T.nilable(String)
      const :arch, T.nilable(String)
    end

    class HLKPlatform < T::Struct
      extend T::Sig
      extend JsonHelper

      prop :short, T.nilable(String)

      const :name, String
      const :client_iso, T.nilable(String)
      const :kit, String
      const :setupmanager, String
      const :fw_type, String, default: 'uefi'
      const :tpm_state, T::Boolean, default: false
      const :enlightenments_state, T.nilable(T::Boolean)
      const :cpu, T.nilable(String)
      const :clients_options, HLKPlatformClientsOptions, factory: -> { HLKPlatformClientsOptions.new }
      const :st_image, T.nilable(String)
      const :client_arch, T.nilable(String)
      const :clients, T::Hash[String, HLKClient]
      const :extra_software, T::Array[String], default: []

      sig { params(hash: T::Hash[String, T.untyped], strict: T::Boolean).void }
      # This is Sorbet function, so we can't change the signature
      # rubocop:disable Style/OptionalBooleanParameter
      def deserialize(hash, strict = false)
        super

        validate_qemuhck if setupmanager == 'qemuhck'
      end
      # rubocop:enable Style/OptionalBooleanParameter

      private

      sig { void }
      def validate_qemuhck
        raise(InvalidConfigFile, 'HLKPlatform: st_image is required for qemuhck') if st_image.nil?

        if clients.values.any? { |client| client.client_iso.nil? } && client_iso.nil?
          raise(InvalidConfigFile, 'HLKPlatform: client_iso is required for all clients or for the platform')
        end

        clients.each_value { |client| validate_qemuhck_client(client) }
      end

      sig { params(client: HLKClient).void }
      def validate_qemuhck_client(client)
        raise(InvalidConfigFile, 'HLKPlatform: client.cpus is required for qemuhck') if client.cpus.nil?
        raise(InvalidConfigFile, 'HLKPlatform: client.memory_gb is required for qemuhck') if client.memory_gb.nil?
        raise(InvalidConfigFile, 'HLKPlatform: client.winrm_addr is required for qemuhck') if client.winrm_addr.nil?
        raise(InvalidConfigFile, 'HLKPlatform: client.image is required for qemuhck') if client.image.nil?
      end
    end
  end
end
