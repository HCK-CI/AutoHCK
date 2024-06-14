# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # SysInfoParser class
  class SysInfoParser
    # Main text parsing function
    #
    # @param data [String] Text data to parse
    #
    # @return [Hash] Dictionary with processed structured data.
    def parse(data)
      CSV.parse(data, headers: true).first.each.to_h do |k, v|
        [
          k,
          case k
          when 'Hotfix(s)', 'Processor(s)'
            parse_hotfixs_or_processors v
          else
            v.strip
          end
        ]
      end
    end

    private

    # Turns a list of return-delimited hotfixes or processors
    # with [x] as a prefix into an array of hotfixes
    #
    # Parameters:
    #   data: (string) Input string
    def parse_hotfixs_or_processors(data)
      arr_output = data.split(',')
      # skip line that says how many are installed
      arr_output.shift
      # discard the number sequence
      arr_output.map! { _1.split(':')[1].strip }
    end
  end
end
