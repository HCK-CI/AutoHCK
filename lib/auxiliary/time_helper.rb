# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # Helper module
  module Helper
    def time_to_seconds(time_string)
      match = time_string.match(/^(?:(\d+)\.)?(?:(\d+):)?(\d+)(?::(\d+(?:\.\d+)?))?$/)

      return 0 unless match

      days = match[1].to_i
      hours = match[2].to_i
      minutes = match[3].to_i
      seconds = match[4].to_f

      (((((days * 24) + hours) * 60) + minutes) * 60) + seconds
    end

    def seconds_to_time(sec)
      format('%<h>.02d:%<m>.02d:%<s>.02d', h: sec / 60 / 60, m: sec / 60 % 60, s: sec % 60)
    end

    def time_diff(start, finish)
      ((finish - start) * 24 * 60 * 60).to_i
    end

    def current_timestamp
      Time.now.strftime('%Y_%m_%d_%H_%M_%S')
    end
  end
end
