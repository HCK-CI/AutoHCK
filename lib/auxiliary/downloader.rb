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

      client = HTTPClient.new

      head = client.head(url, follow_redirect: true)
      raise(AutoHCKError, "Download failed with code #{head.status}") unless head.status == 200

      total_size = head.headers['Content-Length'].to_i

      File.open(path, 'wb') do |file|
        client.get(url, follow_redirect: true) do |chunk|
          file.write(chunk)
          log_progress(total_size, file.size)
        end
      end
    end
  end
end
