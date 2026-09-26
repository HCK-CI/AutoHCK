# frozen_string_literal: true

require 'json'

module AutoHCK
  class QemuMachine
    # Virtio PCI transport mode helpers (CLI / QEMU device props / qtree checks).
    class VirtioMode
      # Single source of truth for mode → disable-legacy / disable-modern
      EXPECTED = {
        'modern' => { 'disable-legacy' => 'on', 'disable-modern' => 'off' },
        'legacy' => { 'disable-legacy' => 'off', 'disable-modern' => 'on' },
        'transitional' => { 'disable-legacy' => 'off', 'disable-modern' => 'off' }
      }.freeze

      MODES = EXPECTED.keys.freeze

      # QEMU device names that have @virtio_dut_mode_param@ + guest profiles
      SUPPORTED_DEVICES = %w[
        virtio-rng-pci
        virtio-net-pci
        virtio-blk-pci
        virtio-scsi-pci
        virtio-serial-pci
        virtio-balloon-pci
      ].freeze

      class << self
        def validate!(mode)
          return if mode.nil? || mode.to_s.empty?
          return if MODES.include?(mode.to_s)

          raise AutoHCKError,
                "Invalid virtio mode '#{mode}'; expected one of: #{MODES.join(', ')}"
        end

        def qemu_device_suffix(mode)
          return '' if mode.nil? || mode.to_s.empty?

          validate!(mode)
          EXPECTED.fetch(mode.to_s).map { |key, value| ",#{key}=#{value}" }.join
        end

        # Call when --virtio-mode is set. +devices+ = QEMU device names from -d.
        def validate_devices_for_mode!(mode, devices)
          return if mode.nil? || mode.to_s.empty?

          validate!(mode)
          list = Array(devices).compact
          raise AutoHCKError, '--virtio-mode requires -d <driver>' if list.empty?

          unsupported = list.reject { |d| SUPPORTED_DEVICES.include?(d) }
          return if unsupported.empty?

          raise AutoHCKError,
                "--virtio-mode is not supported for device(s): #{unsupported.join(', ')}. " \
                "Supported: #{SUPPORTED_DEVICES.join(', ')} " \
                '(drivers: viorng, NetKVM, viostor, vioscsi, vioserial, Balloon)'
        end

        def validate_qtree!(qtree_text, device_type, virtio_mode)
          qtree_text = decode_captured_qtree(qtree_text)
          validate_qtree_inputs!(qtree_text, device_type, virtio_mode)
          match_qtree_device!(qtree_text, device_type, virtio_mode)
        end

        private

        def validate_qtree_inputs!(qtree_text, device_type, virtio_mode)
          raise AutoHCKError, 'qtree output is empty' if qtree_text.to_s.strip.empty?
          raise AutoHCKError, 'virtio_qtree_device_type is not set' if device_type.to_s.strip.empty?
          raise AutoHCKError, 'virtio_mode is not set' if virtio_mode.to_s.strip.empty?
        end

        def match_qtree_device!(qtree_text, device_type, virtio_mode)
          validate!(virtio_mode)
          expected = EXPECTED.fetch(virtio_mode.to_s)
          sections = qtree_sections_for_device(qtree_text.to_s, device_type.to_s)

          raise_device_not_found!(device_type) if sections.empty?

          props = sections.find { |p| properties_match_expected?(p, expected) }
          return if props

          report_qtree_mismatch!(sections.first, device_type, virtio_mode)
        end

        def raise_device_not_found!(device_type)
          raise AutoHCKError,
                "device type '#{device_type}' not found in qtree (tp-qemu verify_virtio_mode_qtree)"
        end

        def report_qtree_mismatch!(sample, device_type, virtio_mode)
          raise AutoHCKError,
                "no #{device_type} node in qtree matches virtio_mode=#{virtio_mode} " \
                "(e.g. disable-legacy=#{normalize_qtree_bool(sample['disable-legacy'])}, " \
                "disable-modern=#{normalize_qtree_bool(sample['disable-modern'])})"
        end

        # Functest stores QMP string returns via capture_value -> .to_json
        def decode_captured_qtree(text)
          s = text.to_s.strip
          return s if s.empty?

          return JSON.parse(s) if s.start_with?('"')

          s
        rescue JSON::ParserError
          s
        end

        def properties_match_expected?(props, expected)
          expected.all? do |key, want|
            normalize_qtree_bool(props[key]) == want
          end
        end

        def qtree_sections_for_device(qtree, device_type)
          qtree.split(/\n(?=\s*dev:)/)
               .select { |s| s.include?(device_type) }
               .map { |section| parse_qtree_section(section) }
        end

        def parse_qtree_section(section)
          {
            'disable-legacy' => qtree_property(section, 'disable-legacy'),
            'disable-modern' => qtree_property(section, 'disable-modern')
          }
        end

        # QEMU qtree: disable-legacy = "on"  or  disable-modern = false
        def qtree_property(section, name)
          m = section.match(/#{name}\s*=\s*(?:"([^"]*)"|(\S+))/)
          m && (m[1] || m[2])
        end

        def normalize_qtree_bool(value)
          return nil if value.nil?

          case value.to_s.strip.downcase
          when 'on', 'true' then 'on'
          when 'off', 'false' then 'off'
          else value.to_s.strip.downcase
          end
        end
      end
    end
  end
end
