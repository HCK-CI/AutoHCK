# typed: true
# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # Playlist class
  class Playlist
    extend T::Sig
    include Helper

    attr_reader :rejected_test, :playlist

    def initialize(client, project, target, tools, kit)
      @machine = client.name
      @project = project
      @target = target
      @tools = tools
      @logger = project.logger
      @kit = kit

      @playlist = if @project.options.test.playlist.nil?
                    ms_playlist(true)
                  else
                    custom_playlist
                  end

      @rejected_test = T.let([], T::Array[Models::HLK::Test])
      @tests = T.let([], T::Array[Models::HLK::Test])
    end

    # A custom ListTests error exception
    class ListTestsError < AutoHCKError; end

    sig { params(test: Models::HLK::Test).returns(String) }
    def info_page_url(test)
      # TODO: Add check that URL returns 200 (OK), not 404 (Not Found)
      "https://docs.microsoft.com/en-us/windows-hardware/test/hlk/testref/#{test.id}"
    end

    sig { params(log: T::Boolean).returns(T::Array[Models::HLK::Test]) }
    def list_tests(log)
      return @tests = [] if @target.nil?

      @tests = @tools.list_tests(@target['key'], @machine, @project.engine_tag,
                                 @playlist)

      @tests.each do |t|
        t.url = info_page_url(t)
      end

      custom_select_test_names(log)
      custom_reject_test_names(log)
      sort_by_duration
    end

    def update_target(target)
      @target = target
    end

    sig { params(log: T::Boolean).returns(T.nilable(String)) }
    def ms_playlist(log)
      kit = @kit
      playlists_path = @project.engine.config.playlists_path

      file = kit[0..2] == 'HLK' ? "#{playlists_path}/#{kit[3..]}.xml" : nil
      workspace_file = "#{@project.workspace_path}/playlist_#{kit[3..]}.xml"

      return nil if file.nil? || !File.exist?(file)

      FileUtils.cp(file, workspace_file)

      @logger.info("Applying microsoft's playlist") if log
      workspace_file
    end

    sig { returns(String) }
    def custom_playlist
      playlist = @project.options.test.playlist

      workspace_file = "#{@project.workspace_path}/playlist_#{@kit[3..]}.xml"

      FileUtils.cp(playlist, workspace_file)

      @logger.info("Applying custom kit playlist from #{playlist}")
      workspace_file
    end

    sig { returns(T::Array[Models::HLK::Test]) }
    def sort_by_duration
      @tests.sort_by!(&:duration)
    end

    def intersect_select_tests(select_test_names)
      select_test_names_counted = select_test_names.tally

      @tests.select! do |test|
        next unless select_test_names_counted.key?(test.name)

        test.run_count = select_test_names_counted[test.name] if @project.options.test.allow_test_duplication

        true
      end
    end

    def custom_select_test_names(log)
      user_select_test_names_file = @project.options.test.select_test_names

      select_test_names = if user_select_test_names_file.nil?
                            @project.engine.target['select_test_names']
                          else
                            File.readlines(user_select_test_names_file, chomp: true)
                          end

      return unless select_test_names

      intersect_select_tests(select_test_names)

      count = @tests.count
      @logger.info("Applying custom selected test names, #{count} tests.") if log
    end

    def reject_test_names
      user_reject_test_names_file = @project.options.test.reject_test_names

      if user_reject_test_names_file.nil?
        @project.engine.target['reject_test_names']
      else
        File.readlines(user_reject_test_names_file, chomp: true)
      end
    end

    def custom_reject_test_names(log)
      @rejected_test = []
      return unless reject_test_names

      @tests.reject! do |test|
        if reject_test_names.include?(test.name)
          test.is_skipped = true
          @rejected_test << test
          true
        else
          false
        end
      end
      @logger.info("Applying custom rejected test names, selected #{@tests.count} tests") if log
    end
  end
end
