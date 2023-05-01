# frozen_string_literal: true

require 'optparse'
require './lib/version'

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
      attr_accessor :debug, :config, :client_world_net

      def create_parser(sub_parser)
        OptionParser.new do |parser|
          parser.banner = 'Usage: auto_hck.rb [common options] <command> [command options]'
          parser.separator ''
          define_options(parser)
          parser.on_tail('-h', '--help', 'Show this message') do
            puts parser
            sub_parser&.each do |_k, v|
              puts v
            end
            exit
          end
        end
      end

      def define_options(parser)
        @debug = false
        @config = nil
        @client_world_net = false
        debug_option(parser)
        config_option(parser)
        client_world_net_option(parser)
        version_option(parser)
      end

      def debug_option(parser)
        parser.on('--debug', TrueClass,
                  'Printing debug information') do |debug|
          @debug = debug
        end
      end

      def config_option(parser)
        parser.on('--config <override.json>', String,
                  'Path to custom override.json file') do |config|
          @config = config
        end
      end

      def client_world_net_option(parser)
        parser.on('--client_world_net', TrueClass,
                  'Attach world bridge to clients VM') do |client_world_net|
          @client_world_net = client_world_net
        end
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
      attr_accessor :platform, :drivers, :driver_path, :commit, :diff_file, :svvp, :manual,
                    :gthb_context_prefix, :gthb_context_suffix

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

      def define_options(parser)
        platform_option(parser)
        drivers_option(parser)
        driver_path_option(parser)
        commit_option(parser)
        diff_file_option(parser)
        svvp_option(parser)
        manual_option(parser)
        gthb_context_prefix_option(parser)
        gthb_context_suffix_option(parser)
      end

      def platform_option(parser)
        parser.on('-p', '--platform <platform_name>', String,
                  'Platform for run test') do |platform|
          @platform = platform
        end
      end

      def drivers_option(parser)
        parser.on('-d', '--drivers <drivers_list>', Array,
                  'List of driver for run test') do |drivers|
          @drivers = drivers
        end
      end

      def driver_path_option(parser)
        parser.on('--driver-path <driver_path>', String,
                  'Path to the location of the driver wanted to be tested') do |driver_path|
          @driver_path = driver_path
        end
      end

      def commit_option(parser)
        parser.on('-c', '--commit <commit_hash>', String,
                  'Commit hash for CI status update') do |commit|
          @commit = commit
        end
      end

      def diff_file_option(parser)
        parser.on('--diff <diff_file>', String,
                  'Path to text file containing a list of changed source files') do |diff_file|
          @diff_file = diff_file
        end
      end

      def svvp_option(parser)
        parser.on('--svvp', TrueClass,
                  'Run SVVP tests for specified platform instead of driver tests') do |svvp|
          @svvp = svvp
        end
      end

      def manual_option(parser)
        parser.on('--manual', TrueClass,
                  'Run and prepare the machine for tests, but do not run the tests themselves') do |manual|
          @manual = manual
        end
      end

      def gthb_context_prefix_option(parser)
        parser.on('--gthb_context_prefix <gthb_context_prefix>', String,
                  'Add custom prefix for GitHub CI results context') do |gthb_context_prefix|
          @gthb_context_prefix = gthb_context_prefix
        end
      end

      def gthb_context_suffix_option(parser)
        parser.on('--gthb_context_suffix <gthb_context_suffix>', String,
                  'Add custom suffix for GitHub CI results context') do |gthb_context_suffix|
          @gthb_context_suffix = gthb_context_suffix
        end
      end
    end

    # class InstallOptions
    class InstallOptions
      attr_accessor :platform, :force

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

        platform_option(parser)
        force_option(parser)
      end

      def platform_option(parser)
        parser.on('-p', '--platform <platform_name>', String,
                  'Install VM for specified platform') do |platform|
          @platform = platform
        end
      end

      def force_option(parser)
        parser.on('-f', '--force', TrueClass,
                  'Install all VM, replace studio if exist') do |force|
          @force = force
        end
      end
    end

    def parse(args)
      @parser.order!(args)
      @mode = args.shift
      @sub_parser[@mode]&.order!(args) unless @mode.nil?
    end
  end
end
