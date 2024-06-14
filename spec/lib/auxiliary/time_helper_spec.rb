# frozen_string_literal: true

require_relative '../../../lib/all'

describe AutoHCK::Helper do
  include AutoHCK::Helper

  describe '#time_to_seconds' do
    # Define test cases with time strings and their expected second counts,
    # with explicit calculations for clarity.
    time_conversion_cases = {
      # Format: hh:mm
      '1:2' => (1 * 60 * 60) + (2 * 60), # 1 hour and 2 minutes in seconds
      # Format: hh:mm:ss
      '1:2:3' => (1 * 60 * 60) + (2 * 60) + 3, # 1 hour, 2 minutes, and 3 seconds
      # Format: dd.hh:mm
      '1.2:3' => (1 * 86_400) + (2 * 60 * 60) + (3 * 60), # 1 day, 2 hours, and 3 minutes
      # Format: dd.hh:mm:ss
      '1.2:3:4' => (1 * 86_400) + (2 * 60 * 60) + (3 * 60) + 4, # 1 day, 2 hours, 3 minutes, and 4 seconds
      # Format: hh:mm:ss.ff
      '1:2:3.22' => (1 * 60 * 60) + (2 * 60) + 3.22, # 1 hour, 2 minutes, and 3.22 seconds
      # Format: dd.hh:mm:ss.ff
      '1.2:3:4.22' => (1 * 86_400) + (2 * 60 * 60) + (3 * 60) + 4.22 # 1 day, 2 hours, 3 minutes, and 4.22 seconds
    }

    time_conversion_cases.each do |time_string, seconds|
      it "correctly converts '#{time_string}' to #{seconds} seconds" do
        expect(time_to_seconds(time_string)).to eq(seconds)
      end
    end
  end
end
