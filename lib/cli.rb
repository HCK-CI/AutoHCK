# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # class CLI
  class CLI
    attr_reader :common, :install, :test, :mode

    def initialize
      @common = CommonOptions.new
      @test = TestOptions.new
      @install = InstallOptions.new

      @sub_parser = {
        'test' => @test.create_parser,
        'install' => @install.create_parser
      }

      @parser = @common.create_parser(@sub_parser)
    end

    # class CommonOptions
    class CommonOptions
      attr_accessor :verbose, :config, :client_world_net, :id, :share_on_host_path, :workspace_path

      def create_parser(sub_parser)
        OptionParser.new do |parser|
          parser.banner = 'Usage: auto_hck.rb [common options] <command> [command options]'
          parser.separator ''
          define_options(parser)
          parser.on_tail('-h', '--help', 'Show this message') do
            puts parser
            sub_parser&.each_value do |v|
              puts v
            end
            exit
          end
        end
      end

      # rubocop:disable Metrics/MethodLength
      def define_options(parser)
        @verbose = false
        @config = nil
        @client_world_net = false
        @id = 2
        @share_on_host_path = nil

        parser.on('--share-on-host-path <path>', String,
                  'For using Transfer Network specify the directory to share on host machine') do |share_on_host_path|
          @share_on_host_path = share_on_host_path
        end

        parser.on('--verbose', TrueClass,
                  'Enable verbose logging',
                  &method(:verbose=))

        parser.on('--config <override.json>', String,
                  'Path to custom override.json file',
                  &method(:config=))

        parser.on('--client_world_net', TrueClass,
                  'Attach world bridge to clients VM',
                  &method(:client_world_net=))

        parser.on('--id <id>', Integer,
                  'Set ID for AutoHCK run',
                  &method(:id=))

        parser.on('-v', '--version',
                  'Display version information and exit') do
          puts "AutoHCK Version: #{AutoHCK::VERSION}"
          exit
        end

        parser.on('-w <path>', String,
                  'Internal use only',
                  &method(:workspace_path=))
      end
      # rubocop:enable Metrics/MethodLength
    end

    # class TestOptions
    class TestOptions
      attr_accessor :platform, :drivers, :driver_path, :commit, :svvp, :dump,
                    :gthb_context_prefix, :gthb_context_suffix, :playlist, :select_test_names,
                    :reject_test_names, :reject_report_sections, :boot_device,
                    :allow_test_duplication, :manual, :package_with_playlist

      def create_parser
        OptionParser.new do |parser|
          parser.banner = 'Usage: auto_hck.rb test [test options]'
          parser.separator ''
          define_options(parser)
          parser.on_tail('-h', '--help', 'Show this message') do
            puts parser
            exit
          end
        end
      end

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def define_options(parser)
        @reject_report_sections = []

        parser.on('-p', '--platform <platform_name>', String,
                  'Platform for run test',
                  &method(:platform=))

        parser.on('-d', '--drivers <drivers_list>', Array,
                  'List of driver for run test',
                  &method(:drivers=))

        parser.on('--driver-path <driver_path>', String,
                  'Path to the location of the driver wanted to be tested',
                  &method(:driver_path=))

        parser.on('-c', '--commit <commit_hash>', String,
                  'Commit hash for CI status update',
                  &method(:commit=))

        parser.on('--svvp', TrueClass,
                  'Run SVVP tests for specified platform instead of driver tests',
                  &method(:svvp=))

        parser.on('--dump', TrueClass,
                  'Create machines snapshots and generate scripts for run it manualy',
                  &method(:dump=))

        parser.on('--gthb_context_prefix <gthb_context_prefix>', String,
                  'Add custom prefix for GitHub CI results context',
                  &method(:gthb_context_prefix=))

        parser.on('--gthb_context_suffix <gthb_context_suffix>', String,
                  'Add custom suffix for GitHub CI results context',
                  &method(:gthb_context_suffix=))

        parser.on('--playlist <playlist>', String,
                  'Use custom Microsoft XML playlist',
                  &method(:playlist=))

        parser.on('--select-test-names <select_test_names>', String,
                  'Use custom user text playlist',
                  &method(:select_test_names=))

        parser.on('--reject-test-names <reject_test_names>', String,
                  'Use custom CI text ignore list',
                  &method(:reject_test_names=))

        parser.on('--reject-report-sections <reject_report_sections>', Array,
                  'List of section to reject from HTML results',
                  '(use "--reject-report-sections=help" to list sections)') do |reject_report_sections|
          if reject_report_sections.first == 'help'
            puts Tests::RESULTS_REPORT_SECTIONS.join("\n")
            exit
          end

          extra_keys = reject_report_sections - Tests::RESULTS_REPORT_SECTIONS

          raise(AutoHCKError, "Unknown report sections: #{extra_keys.join(', ')}.") unless extra_keys.empty?

          @reject_report_sections = reject_report_sections
        end

        parser.on('--boot-device <boot_device>', String,
                  'VM boot device',
                  &method(:boot_device=))

        parser.on('--allow-test-duplication', TrueClass,
                  'Allow run the same test several times.',
                  'Works only with custom user text playlist.',
                  'Test results table can be broken. (experimental)',
                  &method(:allow_test_duplication=))

        parser.on('--manual', TrueClass,
                  'Run AutoHCK in manual mode',
                  &method(:manual=))

        parser.on('--package-with-playlist', TrueClass,
                  'Load playlist into HLKX project package',
                  &method(:package_with_playlist=))
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    end

    # class InstallOptions
    class InstallOptions
      attr_accessor :platform, :force, :skip_client, :drivers, :driver_path, :debug

      def create_parser
        OptionParser.new do |parser|
          parser.banner = 'Usage: auto_hck.rb install [install options]'
          parser.separator ''
          define_options(parser)
          parser.on_tail('-h', '--help', 'Show this message') do
            puts parser
            exit
          end
        end
      end

      # rubocop:disable Metrics/MethodLength
      def define_options(parser)
        @force = false
        @skip_client = false
        @drivers = []
        @debug = false

        parser.on('--debug', TrueClass, 'Enable debug mode',
                  &method(:debug=))

        parser.on('-p', '--platform <platform_name>', String,
                  'Install VM for specified platform',
                  &method(:platform=))

        parser.on('-f', '--force', TrueClass,
                  'Install all VM, replace studio if exist',
                  &method(:force=))

        parser.on('--skip_client', TrueClass,
                  'Skip client images installation',
                  &method(:skip_client=))

        parser.on('-d', '--drivers <drivers_list>', Array,
                  'List of driver attach in install',
                  &method(:drivers=))

        parser.on('--driver-path <driver_path>', String,
                  'Path to the location of the driver wanted to be installed',
                  &method(:driver_path=))
      end
      # rubocop:enable Metrics/MethodLength
    end

    def parse(args)
      left = @parser.order(args)
      @mode = left.shift
      @sub_parser[@mode]&.order!(left) unless @mode.nil?
    end
  end
end
