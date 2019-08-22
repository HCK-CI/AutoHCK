# frozen_string_literal: true

# Playlist class
class Playlist
  def initialize(client, project, target, tools)
    @machine = client.name
    @project = project
    @target = target
    @tools = tools
    @logger = project.logger
    @ms_playlist = ms_playlist(true)
  end

  # A custom ListTests error exception
  class ListTestsError < AutoHCKError; end

  def list_tests(log)
    @tests = @tools.list_tests(@target['key'], @machine, @project.tag,
                               @ms_playlist)
    raise ListTestsError, 'Failed to list tests' unless @tests

    custom_playlist(log)
    custom_blacklist(log)
    sort_by_duration
  end

  def update_target(target)
    @target = target
  end

  def ms_playlist(log)
    kit = @project.platform['kit']
    file = kit[0..2] == 'HLK' ? "./playlists/#{kit[3..-1]}.xml" : nil
    return nil if file.nil? || !File.exist?("./#{file}")

    @logger.info("Applying microsoft's playlist") if log
    file
  end

  def time_to_seconds(time)
    time.split(':') .reverse .map .with_index { |a, i| a.to_i * (60**i) }
        .reduce(:+)
  end

  def sort_by_duration
    @tests.each_with_index do |x, i|
      @tests[i]['duration'] = time_to_seconds(x['estimatedruntime'])
    end
    @tests.sort_by! { |test| test['duration'] }
  end

  def custom_playlist(log)
    playlist = @project.device['playlist']
    return unless playlist

    @tests.select! { |test| playlist.include?(test['name']) }
    count = @tests.count
    @logger.info("Applying custom playlist, #{count} tests.") if log
  end

  def custom_blacklist(log)
    blacklist = @project.device['blacklist']
    @tests.reject! { |test| blacklist.include?(test['name']) } if blacklist
    @logger.info('Applying custom blacklist') if log && blacklist
  end
end
