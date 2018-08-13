require 'optparse'

# class CLI
class CLI
  # class ScriptOptions
  class ScriptOptions
    attr_accessor :tag, :path, :diff, :commit, :debug
    def define_options(parser)
      self.debug = false
      parser.banner = 'Usage: auto_hck.rb [options]'
      parser.separator ''
      mandatory_options(parser)
      optional_options(parser)
      parser.on_tail('-h', '--help', 'Show this message') do
        puts parser
        exit
      end
    end

    def mandatory_options(parser)
      parser.separator 'Mandatory:'
      tag_option(parser)
      path_option(parser)
    end

    def optional_options(parser)
      parser.separator 'Optional:'
      commit_option(parser)
      diff_option(parser)
      debug_option(parser)
    end

    def commit_option(parser)
      parser.on('-c', '--commit <COMMITHASH>',
                'Commit hash for CI status update') do |commit|
        self.commit = commit
      end
    end

    def diff_option(parser)
      parser.on('-d', '--diff <DIFFFILE>',
                'Text file containing a list of files changed') do |diff|
        self.diff = diff
      end
    end

    def tag_option(parser)
      parser.on('-t', '--tag [PROJECT-PLATFORM]',
                'Tag name consist of project name and platform separated by a '\
                'dash') do |tag|
        self.tag = tag
      end
    end

    def path_option(parser)
      parser.on('-p', '--path [DRIVERPATH]',
                'Path to the location of the driver wanted to be '\
                'tested') do |path|
        self.path = path
      end
    end

    def debug_option(parser)
      parser.on('--debug',
                'Printing debug information') do |debug|
        self.debug = debug
      end
    end
  end

  def parse(args)
    @options = ScriptOptions.new
    @args = OptionParser.new do |parser|
      @options.define_options(parser)
      parser.parse!(args)
    end
    @options
  end

  attr_reader :parser, :options
end
