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

        @boot_image_path = Pathname.new(qemu_config['images_path']).join(qemu_options['image_name'])
        @test_image_path = Pathname.new(@workspace_path).join("client#{@client_id}_test_image.#{IMAGE_FORMAT}")
      end

      def read_device(device)
        @logger.info("Loading device: #{device}")
        device_json = "#{DEVICES_JSON_DIR}/#{device}.json"
        Json.read_json(device_json, @logger)
      end

      def device_command_info(type, device_name, command_options, qemu_replacement_map)
        device = read_device(device_name)
        replacement_map = qemu_replacement_map.merge command_options
        device_command = replacement_map.create_cmd(device['command_line'].join(' '))

        @logger.debug("Device #{device_name} used as #{type} device")
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

      def create_image(path, size_gb)
        run_cmd(*%W[#{@qemu_img_bin} create -f #{IMAGE_FORMAT} #{path} #{size_gb}G])
      end

      def create_boot_image
        create_image(@boot_image_path, 150)
      end

      def create_test_image
        if File.exist?(@fs_test_image)
          @logger.info("Coping test image for CL#{@client_id}")
          FileUtils.cp(@fs_test_image, @test_image_path)
        else
          @logger.info("Creating CL#{@client_id} test image")
          create_image(@test_image_path, 30)
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

      def boot_device_command(device_name, run_opts, qemu_replacement_map)
        create_boot_snapshot if run_opts[:create_snapshot]
        image_path = run_opts[:create_snapshot] ? boot_snapshot_path : @boot_image_path

        options = {
          '@image_format@' => IMAGE_FORMAT,
          '@image_path@' => image_path
        }

        [device_command_info('boot', device_name, options, qemu_replacement_map), image_path]
      end

      def test_device_command(device_name, qemu_replacement_map)
        create_test_image

        options = {
          '@image_format@' => IMAGE_FORMAT,
          '@image_path@' => @test_image_path
        }

        device_command_info('test', device_name, options, qemu_replacement_map)
      end
    end
  end
end
