# typed: true
# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # PackageManager class for cross-platform package queries
  class PackageManager
    extend T::Sig

    SUPPORTED_DISTROS = {
      'ubuntu' => :debian,
      'debian' => :debian,
      'centos' => :rhel,
      'rhel' => :rhel,
      'rocky' => :rhel,
      'almalinux' => :rhel,
      'fedora' => :fedora,
      'arch' => :arch,
      'manjaro' => :arch
    }.freeze

    sig { params(logger: T.untyped).void }
    def initialize(logger)
      @logger = logger
      @distro_info = detect_distro
    end

    sig { params(binary_path: String).returns(T.nilable(String)) }
    def query_package(binary_path)
      return nil if binary_path.empty?

      query_method = distro_query_method
      return unsupported_platform_warning unless query_method

      send(query_method, binary_path)
    rescue StandardError => e
      @logger.warn("Failed to query package for #{binary_path}: #{e.message}")
      nil
    end

    private

    sig { returns(T.nilable(Symbol)) }
    def distro_query_method
      {
        debian: :query_debian_package,
        rhel: :query_rhel_package,
        fedora: :query_rhel_package,
        fedora_immutable: :query_rhel_package,
        arch: :query_arch_package
      }[@distro_info[:family]]
    end

    sig { returns(T.nilable(String)) }
    def unsupported_platform_warning
      @logger.warn("Unsupported platform: #{@distro_info[:name]} (#{@distro_info[:family]})")
      nil
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def detect_distro
      # Check for common distribution identification files
      return parse_os_release if File.exist?('/etc/os-release')
      return parse_lsb_release if File.exist?('/etc/lsb-release')
      return parse_redhat_release if File.exist?('/etc/redhat-release')

      { name: 'unknown', family: :unknown }
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def parse_os_release
      content = File.read('/etc/os-release')
      id = content[/^ID=(.+)/, 1]&.gsub(/["']/, '')&.downcase

      return { name: 'unknown', family: :unknown } unless id

      return parse_fedora_release(content, id) if id == 'fedora'

      family = SUPPORTED_DISTROS[id] || :unknown
      { name: id, family: family }
    end

    sig { params(content: String, id: String).returns(T::Hash[Symbol, T.untyped]) }
    def parse_fedora_release(content, id)
      # Check if it's Fedora Silverblue/Kinoite
      variant = content[/^VARIANT_ID=(.+)/, 1]&.gsub(/["']/, '')&.downcase
      family = fedora_immutable_variant?(variant) ? :fedora_immutable : :fedora
      { name: id, family: family, variant: variant }
    end

    sig { params(variant: T.nilable(String)).returns(T::Boolean) }
    def fedora_immutable_variant?(variant)
      return false unless variant

      variant.include?('silverblue') || variant.include?('kinoite')
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def parse_lsb_release
      content = File.read('/etc/lsb-release')
      id = content[/^DISTRIB_ID=(.+)/, 1]&.gsub(/["']/, '')&.downcase

      family = id ? SUPPORTED_DISTROS[id] || :unknown : :unknown
      { name: id || 'unknown', family: family }
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def parse_redhat_release
      content = File.read('/etc/redhat-release').downcase

      if content.include?('centos')
        { name: 'centos', family: :rhel }
      elsif content.include?('red hat')
        { name: 'rhel', family: :rhel }
      elsif content.include?('fedora')
        { name: 'fedora', family: :fedora }
      else
        { name: 'unknown', family: :unknown }
      end
    end

    sig { params(binary_path: String).returns(T.nilable(String)) }
    def query_debian_package(binary_path)
      # Use dpkg -S to find which package owns the file
      result = `dpkg -S "#{binary_path}" 2>/dev/null`
      return nil if $CHILD_STATUS.exitstatus != 0 || result.empty?

      # dpkg -S output format: "package: /path/to/file"
      package = result.split(':').first&.strip
      return nil unless package

      # Get the full package version
      version_result = `dpkg -l "#{package}" 2>/dev/null | tail -1`
      return package if version_result.empty?

      # dpkg -l output format: "ii  package  version  arch  description"
      parts = version_result.split
      return package unless parts.length >= 3

      "#{package}_#{parts[2]}_#{parts[3]}"
    end

    sig { params(binary_path: String).returns(T.nilable(String)) }
    def query_rhel_package(binary_path)
      # Use rpm -qf for RHEL/CentOS/Fedora
      # For Fedora Silverblue/immutable, also use rpm -qf (rpm-ostree manages the rpm db)
      if @distro_info[:family] == :fedora_immutable
        @logger.info("Detected Fedora immutable variant (#{@distro_info[:variant]}), using rpm query")
      end

      result = `rpm -qf "#{binary_path}" 2>/dev/null`
      return nil if $CHILD_STATUS.exitstatus != 0 || result.empty?

      result.strip
    end

    sig { params(binary_path: String).returns(T.nilable(String)) }
    def query_arch_package(binary_path)
      # Use pacman -Qo for Arch Linux
      result = `pacman -Qo "#{binary_path}" 2>/dev/null`
      return nil if $CHILD_STATUS.exitstatus != 0 || result.empty?

      # pacman -Qo output format: "/path/to/file is owned by package version"
      match = result.match(/is owned by (.+)/)
      return nil unless match

      T.must(match[1]).strip
    end
  end
end
