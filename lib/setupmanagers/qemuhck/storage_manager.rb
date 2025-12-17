# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # QemuMachine class
  class QemuMachine
    # StorageManager class
    class StorageManager
      include Helper

      IMAGE_FORMAT = 'qcow2'

      def initialize(id, client_id, qemu_config, qemu_options, logger)
        @id = id
        @client_id = client_id
        @logger = logger

        @workspace_path = qemu_options['workspace_path']
        @qemu_img_bin = qemu_config['qemu_img_bin']
        @fs_test_image = qemu_config['fs_test_image']
        @fs_test_image_format = qemu_options['fs_test_image_format'] || IMAGE_FORMAT
        @iso_path = qemu_options['iso_path']

        @boot_image_path = Pathname.new(qemu_config['images_path']).join(qemu_options['image_name'])
        @test_image_path = Pathname.new(@workspace_path).join("client#{@client_id}_test_image.#{@fs_test_image_format}")
      end

      def device_command_info(type, device, command_options, bus_name, qemu_replacement_map)
        replacement_map = qemu_replacement_map.merge command_options
        device_command = replacement_map.merge({ '@bus_name@' => bus_name }).create_cmd(device.command_line.join(' '))

        @logger.debug("Device #{device.name} used as #{type} device")
        @logger.debug("Device command: #{device_command}")

        device_command
      end

      def boot_snapshot_path
        filename = File.basename(@boot_image_path, '.*')
        "#{@workspace_path}/#{filename}-snapshot.#{IMAGE_FORMAT}"
      end

      def check_image_exist
        File.exist?(@boot_image_path)
      end

      def create_image(path, size_gb, image_format)
        run_cmd(*%W[#{@qemu_img_bin} create -f #{image_format} #{path} #{size_gb}G])
      end

      def create_boot_image
        create_image(@boot_image_path, 150, IMAGE_FORMAT)
      end

      def create_test_image
        if File.exist?(@fs_test_image)
          @logger.info("Coping test image for CL#{@client_id}")
          FileUtils.cp(@fs_test_image, @test_image_path)
        else
          @logger.info("Creating CL#{@client_id} test image")
          create_image(@test_image_path, 30, @fs_test_image_format)
        end
      end

      def create_boot_snapshot
        @logger.info("Creating CL#{@client_id} snapshot file")
        run_cmd(*%W[#{@qemu_img_bin} create -f #{IMAGE_FORMAT} -F #{IMAGE_FORMAT}
                    -b #{@boot_image_path} #{boot_snapshot_path}])
      end

      def delete_boot_snapshot
        FileUtils.rm_f(boot_snapshot_path)
      end

      def boot_device_command(device, run_opts, bus_name, qemu_replacement_map)
        create_boot_snapshot if run_opts[:create_snapshot]
        image_path = boot_device_image_path(run_opts)

        options = {
          '@image_format@' => IMAGE_FORMAT,
          '@image_path@' => image_path,
          '@bootindex@' => ',bootindex=1'
        }

        [device_command_info('boot', device, options, bus_name, qemu_replacement_map), image_path]
      end

      def boot_device_image_path(run_opts)
        return boot_snapshot_path if run_opts[:create_snapshot] || run_opts[:boot_from_snapshot]

        @boot_image_path
      end

      def iso_commands(run_opts, _qemu_replacement_map)
        boot_index = 1

        run_opts[:attach_iso_list]&.map do |iso|
          iso_path = Pathname.new(@iso_path).join(iso)
          boot_index += 1

          "-device ide-cd,drive=iso_drive_#{boot_index},bus=ide.#{boot_index},bootindex=#{boot_index} " \
            "-drive file=#{iso_path},if=none,media=cdrom,readonly=on,id=iso_drive_#{boot_index}"
        end
      end

      def test_device_command(device, bus_name, qemu_replacement_map)
        create_test_image

        options = {
          '@image_format@' => @fs_test_image_format,
          '@image_path@' => @test_image_path,
          '@bootindex@' => ''
        }

        device_command_info('test', device, options, bus_name, qemu_replacement_map)
      end
    end
  end
end
