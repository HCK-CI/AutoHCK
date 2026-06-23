# typed: true
# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # Reads client roles from a platform JSON and exposes helpers used by the engine.
  class PlatformClients
    extend T::Sig

    ClientEntry = T.type_alias { T::Hash[String, T.untyped] }

    # Allowed role sets for WHQL platforms.
    WHQL_CONFIGURATIONS = [
      [Models::ClientRole::Dut],
      [Models::ClientRole::Dut, Models::ClientRole::Support]
    ].freeze

    # Minimum roles required for SVVP. Extra stress clients are fine.
    SVVP_REQUIRED_ROLES = [Models::ClientRole::Sut, Models::ClientRole::Master].freeze

    # MC and SC join the pool but skip driver install and HLK target registration.
    POOL_ONLY_ROLES = [Models::ClientRole::Master, Models::ClientRole::Stress].freeze

    sig do
      params(
        platform: Models::HLKPlatform,
        logger: T.any(MultiLogger, ::Logger)
      ).void
    end
    def initialize(platform, logger:)
      @logger = logger
      @entries = build_entries(platform.clients)
      validate!
    end

    # All clients in platform order.
    attr_reader :entries

    # Role for a given machine name.
    sig { params(name: String).returns(Models::ClientRole) }
    def role_for(name)
      entry = @entries.find { |e| e['name'] == name }
      raise InvalidConfigFile, "Unknown client #{name} in platform configuration" if entry.nil?

      entry.fetch('role')
    end

    # First entry whose role matches (nil if not found).
    sig { params(role: Models::ClientRole).returns(T.nilable(ClientEntry)) }
    def entry_for_role(role)
      @entries.find { |e| e['role'] == role }
    end

    # The primary client entry — SUT for SVVP, DUT for WHQL.
    sig { returns(T.nilable(ClientEntry)) }
    def primary_entry
      entry_for_role(Models::ClientRole::Sut) || entry_for_role(Models::ClientRole::Dut)
    end

    sig { params(name: String).returns(T::Boolean) }
    def pool_only?(name)
      POOL_ONLY_ROLES.include?(role_for(name))
    end

    private

    sig { params(clients: T::Hash[String, Models::HLKClient]).returns(T::Array[ClientEntry]) }
    def build_entries(clients)
      clients.map do |key, client|
        client_hash = client.serialize
        role = resolve_role(client_hash)
        client_hash.merge('role' => role, '_key' => key)
      end
    end

    sig { params(client: T::Hash[String, T.untyped]).returns(Models::ClientRole) }
    def resolve_role(client)
      raw_role = client['role']

      if raw_role.nil? || raw_role.to_s.strip.empty?
        raise InvalidConfigFile,
              "Client '#{client['name']}' is missing a 'role' field in the platform JSON."
      end

      Models::ClientRole.deserialize(raw_role.strip.downcase)
    rescue KeyError
      raise InvalidConfigFile, "Client '#{client['name']}' has unknown role #{raw_role.inspect}. " \
                               "Expected one of: #{Models::ClientRole.values.join(', ')}"
    end

    sig { void }
    def validate!
      roles = @entries.map { |e| e.fetch('role') }
      return if valid_whql_configuration?(roles) || valid_svvp_configuration?(roles)

      raise InvalidConfigFile, invalid_roles_message(roles)
    end

    sig { params(roles: T::Array[Models::ClientRole]).returns(T::Boolean) }
    def valid_whql_configuration?(roles)
      WHQL_CONFIGURATIONS.any? { |config| roles.sort_by(&:to_s) == config.sort_by(&:to_s) }
    end

    sig { params(roles: T::Array[Models::ClientRole]).returns(T::Boolean) }
    def valid_svvp_configuration?(roles)
      SVVP_REQUIRED_ROLES.all? { |role| roles.include?(role) }
    end

    sig { params(roles: T::Array[Models::ClientRole]).returns(String) }
    def invalid_roles_message(roles)
      role_list = roles.join(', ')
      whql_list = WHQL_CONFIGURATIONS.map { |c| c.join(', ') }.join(' | ')
      "Invalid platform client roles [#{role_list}]. " \
        "Expected WHQL (#{whql_list}) or SVVP (must include: #{SVVP_REQUIRED_ROLES.join(', ')})."
    end
  end
end
