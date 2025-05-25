# typed: true
# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # class CommonOptions
  class CommonOptions < T::Struct
    include T::Sig

    prop :verbose, T::Boolean, default: false
    prop :config, T.nilable(String)
    prop :client_world_net, T::Boolean, default: false
    prop :id, Integer, default: 2
    prop :share_on_host_path, T.nilable(String)
    prop :workspace_path, T.nilable(String)
    prop :client_ctrl_net_dev, T.nilable(String)

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

      parser.on('--client-ctrl-net-dev <client-ctrl-net-dev>', String,
                'Client VM control network device (make sure that driver is installed)',
                &method(:client_ctrl_net_dev=))

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
  end

  # class TestOptions
  class TestOptions < T::Struct
    include T::Sig

    prop :platform, T.nilable(String)
    prop :drivers, T::Array[String], default: []
    prop :driver_path, T.nilable(String)
    prop :commit, T.nilable(String)
    prop :svvp, T::Boolean, default: false
    prop :dump, T::Boolean, default: false
    prop :gthb_context_prefix, T.nilable(String)
    prop :gthb_context_suffix, T.nilable(String)
    prop :playlist, T.nilable(String)
    prop :select_test_names, T.nilable(String)
    prop :reject_test_names, T.nilable(String)
    prop :reject_report_sections, T::Array[String], default: []
    prop :boot_device, T.nilable(String)
    prop :allow_test_duplication, T::Boolean, default: false
    prop :manual, T::Boolean, default: false
    prop :package_with_playlist, T::Boolean, default: false
    prop :enable_vbs, T::Boolean, default: false
    prop :session, T.nilable(String)
    prop :latest_session, T::Boolean, default: false

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

    def define_options(parser) # rubocop:disable Metrics/AbcSize
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

      parser.on('--session <path>', String,
                'Load session from workspace',
                &method(:session=))

      parser.on('--latest-session', TrueClass,
                'Load previous session',
                &method(:latest_session=))
    end
    # rubocop:enable Metrics/MethodLength
  end

  # class InstallOptions
  class InstallOptions < T::Struct
    include T::Sig

    prop :platform, T.nilable(String)
    prop :force, T::Boolean, default: false
    prop :skip_client, T::Boolean, default: false
    prop :drivers, T::Array[String], default: []
    prop :driver_path, T.nilable(String)
    prop :debug, T::Boolean, default: false

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
  end

  # class CLI
  class CLI < T::Struct
    extend AutoHCK::Models::JsonHelper
    extend T::Sig

    prop :test, TestOptions, factory: -> { TestOptions.new }
    prop :common, CommonOptions, factory: -> { CommonOptions.new }
    prop :install, InstallOptions, factory: -> { InstallOptions.new }
    prop :mode, T.nilable(String), default: nil

    sig { returns(T::Hash[String, OptionParser]) }
    def sub_parser
      {
        'test' => test.create_parser,
        'install' => install.create_parser
      }
    end

    sig { returns(OptionParser) }
    def parser
      common.create_parser(sub_parser)
    end

    sig { params(args: T::Array[String]).returns(T::Array[String]) }
    def parse(args)
      left = parser.order(args)
      @mode = left.shift
      sub_parser[@mode]&.order!(left) unless @mode.nil?
    end
  end
end
