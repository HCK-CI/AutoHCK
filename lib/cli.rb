# frozen_string_literal: true

require 'optparse'
require './lib/version'
require './lib/exceptions'

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
      attr_accessor :verbose, :config, :client_world_net, :id, :share_on_host_path

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

      def define_options(parser)
        @verbose = false
        @config = nil
        @client_world_net = false
        @id = 2
        @share_on_host_path = nil
        verbose_option(parser)
        config_option(parser)
        client_world_net_option(parser)
        id_option(parser)
        version_option(parser)
        share_on_host_path_option(parser)
      end

      def share_on_host_path_option(parser)
        parser.on('--share-on-host-path <path>', String,
                  'For using Transfer Network specify the directory to share on host machine') do |share_on_host_path|
          @share_on_host_path = share_on_host_path
        end
      end

      def verbose_option(parser)
        parser.on('--verbose', TrueClass,
                  'Enable verbose logging',
                  &method(:verbose=))
      end

      def config_option(parser)
        parser.on('--config <override.json>', String,
                  'Path to custom override.json file',
                  &method(:config=))
      end

      def client_world_net_option(parser)
        parser.on('--client_world_net', TrueClass,
                  'Attach world bridge to clients VM',
                  &method(:client_world_net=))
      end

      def id_option(parser)
        parser.on('--id <id>', Integer,
                  'Set ID for AutoHCK run',
                  &method(:id=))
      end

      def version_option(parser)
        parser.on('-v', '--version',
                  'Display version information and exit') do
          puts "AutoHCK Version: #{AutoHCK::VERSION}"
          exit
        end
      end
    end

    # class TestOptions
    class TestOptions
      attr_accessor :platform, :drivers, :driver_path, :commit, :diff_file, :svvp, :dump,
                    :gthb_context_prefix, :gthb_context_suffix, :playlist, :select_test_names,
                    :reject_test_names, :triggers_file, :reject_report_sections, :boot_device,
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

      # rubocop:disable Metrics/AbcSize
      def define_options(parser)
        platform_option(parser)
        drivers_option(parser)
        driver_path_option(parser)
        commit_option(parser)
        diff_file_option(parser)
        svvp_option(parser)
        dump_option(parser)
        gthb_context_prefix_option(parser)
        gthb_context_suffix_option(parser)
        playlist_option(parser)
        select_test_names_option(parser)
        reject_test_names_option(parser)
        triggers_file_option(parser)
        reject_report_sections_option(parser)
        boot_device_option(parser)
        allow_test_duplication_option(parser)
        manual_option(parser)
        package_with_playlist_option(parser)
      end
      # rubocop:enable Metrics/AbcSize

      def platform_option(parser)
        parser.on('-p', '--platform <platform_name>', String,
                  'Platform for run test',
                  &method(:platform=))
      end

      def drivers_option(parser)
        parser.on('-d', '--drivers <drivers_list>', Array,
                  'List of driver for run test',
                  &method(:drivers=))
      end

      def driver_path_option(parser)
        parser.on('--driver-path <driver_path>', String,
                  'Path to the location of the driver wanted to be tested',
                  &method(:driver_path=))
      end

      def commit_option(parser)
        parser.on('-c', '--commit <commit_hash>', String,
                  'Commit hash for CI status update',
                  &method(:commit=))
      end

      def diff_file_option(parser)
        parser.on('--diff <diff_file>', String,
                  'Path to text file containing a list of changed source files',
                  &method(:diff_file=))
      end

      def svvp_option(parser)
        parser.on('--svvp', TrueClass,
                  'Run SVVP tests for specified platform instead of driver tests',
                  &method(:svvp=))
      end

      def dump_option(parser)
        parser.on('--dump', TrueClass,
                  'Create machines snapshots and generate scripts for run it manualy',
                  &method(:dump=))
      end

      def gthb_context_prefix_option(parser)
        parser.on('--gthb_context_prefix <gthb_context_prefix>', String,
                  'Add custom prefix for GitHub CI results context',
                  &method(:gthb_context_prefix=))
      end

      def gthb_context_suffix_option(parser)
        parser.on('--gthb_context_suffix <gthb_context_suffix>', String,
                  'Add custom suffix for GitHub CI results context',
                  &method(:gthb_context_suffix=))
      end

      def playlist_option(parser)
        parser.on('--playlist <playlist>', String,
                  'Use custom Microsoft XML playlist',
                  &method(:playlist=))
      end

      def select_test_names_option(parser)
        parser.on('--select-test-names <select_test_names>', String,
                  'Use custom user text playlist',
                  &method(:select_test_names=))
      end

      def reject_test_names_option(parser)
        parser.on('--reject-test-names <reject_test_names>', String,
                  'Use custom CI text ignore list',
                  &method(:reject_test_names=))
      end

      def triggers_file_option(parser)
        parser.on('--triggers <triggers_file>', String,
                  'Path to text file containing triggers',
                  &method(:triggers_file=))
      end

      def reject_report_sections_option(parser)
        @reject_report_sections = []

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
      end

      def boot_device_option(parser)
        parser.on('--boot-device <boot_device>', String,
                  'VM boot device',
                  &method(:boot_device=))
      end

      def allow_test_duplication_option(parser)
        parser.on('--allow-test-duplication', TrueClass,
                  'Allow run the same test several times.',
                  'Works only with custom user text playlist.',
                  'Test results table can be broken. (experimental)',
                  &method(:allow_test_duplication=))
      end

      def manual_option(parser)
        parser.on('--manual', TrueClass,
                  'Run AutoHCK in manual mode',
                  &method(:manual=))
      end

      def package_with_playlist_option(parser)
        parser.on('--package-with-playlist', TrueClass,
                  'Load playlist into HLKX project package',
                  &method(:package_with_playlist=))
        end
      end
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

      def define_options(parser)
        @force = false
        @skip_client = false
        @drivers = []
        @debug = false

        debug_option(parser)
        platform_option(parser)
        force_option(parser)
        skip_client_option(parser)
        drivers_option(parser)
        driver_path_option(parser)
      end

      def debug_option(parser)
        parser.on('--debug', TrueClass, 'Enable debug mode',
                  &method(:debug=))
      end

      def platform_option(parser)
        parser.on('-p', '--platform <platform_name>', String,
                  'Install VM for specified platform',
                  &method(:platform=))
      end

      def force_option(parser)
        parser.on('-f', '--force', TrueClass,
                  'Install all VM, replace studio if exist',
                  &method(:force=))
      end

      def skip_client_option(parser)
        parser.on('--skip_client', TrueClass,
                  'Skip client images installation',
                  &method(:skip_client=))
      end

      def drivers_option(parser)
        parser.on('-d', '--drivers <drivers_list>', Array,
                  'List of driver attach in install',
                  &method(:drivers=))
      end

      def driver_path_option(parser)
        parser.on('--driver-path <driver_path>', String,
                  'Path to the location of the driver wanted to be installed',
                  &method(:driver_path=))
      end
    end

    def parse(args)
      @parser.order!(args)
      @mode = args.shift
      @sub_parser[@mode]&.order!(args) unless @mode.nil?
    end
  end
end
