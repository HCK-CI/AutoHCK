# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # Downloader class
  class Downloader
    UNITS = %w[B KiB MiB GiB TiB].freeze

    def initialize(logger)
      @logger = logger
    end

    def size_to_str(number)
      if number.to_i < 1024
        exponent = 0
      else
        max_exp = UNITS.size - 1

        # convert to base
        exponent = (Math.log(number) / Math.log(1024)).to_i
        # we need this to avoid overflow for the highest unit
        exponent = max_exp if exponent > max_exp

        number  /= 1024.0**exponent
      end

      "#{number.round(2)} #{UNITS[exponent]}"
    end

    def log_progress(dl_total, dl_now)
      return if dl_total.zero?

      percent = Integer(100 * dl_now / dl_total)

      return if percent - @last_percent < 5 && (percent != 100 || @last_percent == 100)

      @logger.info("Downloaded #{size_to_str(dl_now)} (#{percent}%)")
      @last_percent = percent
    end

    def download(url, path)
      @logger.info("Starting download #{url} to #{path}")

      @last_percent = 0

      result = Curl::Easy.download(url, path) do |curl|
        curl.follow_location = true

        curl.on_progress do |dl_total, dl_now, _ul_total, _ul_now|
          log_progress(dl_total, dl_now)
          true
        end
      end
      raise(AutoHCKError, "Download failed with code #{result.response_code}") if result.response_code != 200
    end
  end
end
