# frozen_string_literal: true

require './lib/auxiliary/time_helper'

# AutoHCK module
module AutoHCK
  # Playlist class
  class Playlist
    include Helper

    attr_reader :rejected_test

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
    end

    # A custom ListTests error exception
    class ListTestsError < AutoHCKError; end

    def list_tests(log)
      @tests = @tools.list_tests(@target['key'], @machine, @project.engine.tag,
                                 @playlist)
      raise ListTestsError, 'Failed to list tests' unless @tests

      custom_select_test_names(log)
      custom_reject_test_names(log)
      sort_by_duration
    end

    def update_target(target)
      @target = target
    end

    def ms_playlist(log)
      kit = @kit
      playlists_path = @project.engine.config['playlists_path']

      file = kit[0..2] == 'HLK' ? "#{playlists_path}/#{kit[3..]}.xml" : nil
      workspace_file = "#{@project.workspace_path}/playlist_#{kit[3..]}.xml"

      return nil if file.nil? || !File.exist?(file)

      FileUtils.cp(file, workspace_file)

      @logger.info("Applying microsoft's playlist") if log
      workspace_file
    end

    def custom_playlist
      playlist = @project.options.test.playlist

      workspace_file = "#{@project.workspace_path}/playlist_#{@kit[3..]}.xml"

      FileUtils.cp(playlist, workspace_file)

      @logger.info("Applying custom kit playlist from #{playlist}")
      workspace_file
    end

    def sort_by_duration
      @tests.each_with_index do |x, i|
        @tests[i]['duration'] = time_to_seconds(x['estimatedruntime'])
      end
      @tests.sort_by! { |test| test['duration'] }
    end

    def custom_select_test_names(log)
      user_select_test_names_file = @project.options.test.select_test_names

      select_test_names = if user_select_test_names_file.nil?
                            @project.engine.target['select_test_names']
                          else
                            File.readlines(user_select_test_names_file, chomp: true)
                          end

      return unless select_test_names

      @tests.select! { |test| select_test_names.include?(test['name']) }
      count = @tests.count
      @logger.info("Applying custom selected test names, #{count} tests.") if log
    end

    def custom_reject_test_names(log)
      user_reject_test_names_file = @project.options.test.reject_test_names

      reject_test_names = if user_reject_test_names_file.nil?
                            @project.engine.target['reject_test_names']
                          else
                            File.readlines(user_reject_test_names_file, chomp: true)
                          end

      @rejected_test = []
      return unless reject_test_names

      @tests.reject! do |test|
        if reject_test_names.include?(test['name'])
          @rejected_test << test
          true
        else
          false
        end
      end
      @logger.info('Applying custom rejected test names') if log
    end
  end
end
