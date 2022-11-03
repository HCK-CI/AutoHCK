# frozen_string_literal: true

require './lib/auxiliary/time_helper'

# AutoHCK module
module AutoHCK
  # Playlist class
  class Playlist
    include Helper

    attr_reader :ignored_list

    def initialize(client, project, target, tools, kit)
      @machine = client.name
      @project = project
      @target = target
      @tools = tools
      @logger = project.logger
      @kit = kit
      @ms_playlist = ms_playlist(true)
    end

    # A custom ListTests error exception
    class ListTestsError < AutoHCKError; end

    def list_tests(log)
      @tests = @tools.list_tests(@target['key'], @machine, @project.engine.tag,
                                 @ms_playlist)
      raise ListTestsError, 'Failed to list tests' unless @tests

      custom_playlist(log)
      custom_ignore_list(log)
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

    def sort_by_duration
      @tests.each_with_index do |x, i|
        @tests[i]['duration'] = time_to_seconds(x['estimatedruntime'])
      end
      @tests.sort_by! { |test| test['duration'] }
    end

    def custom_playlist(log)
      playlist = @project.engine.target['playlist']
      return unless playlist

      @tests.select! { |test| playlist.include?(test['name']) }
      count = @tests.count
      @logger.info("Applying custom playlist, #{count} tests.") if log
    end

    def custom_ignore_list(log)
      ignore_list = @project.engine.target['ignore_list']
      @ignored_list = []
      if ignore_list
        @tests.reject! do |test|
          if ignore_list.include?(test['name'])
            @ignored_list << test
            true
          else
            false
          end
        end
      end
      @logger.info('Applying custom ignore list') if log && ignore_list
    end
  end
end
