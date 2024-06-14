require_relative '../lib/all'

describe 'diff_checker' do
  triggers = 'spec/diff_checker_spec/triggers.yml'
  diffs = 'spec/diff_checker_spec/diff_*.txt'

  Dir[diffs].each do |diff|
    name = File.basename(diff)
    name_parts = name.split('_')

    expect_res = name_parts[3].split('.')[0] == 'pass'
    drivers_name = [name_parts[2]]

    it name.to_s do
      dc = AutoHCK::DiffChecker.new(nil, drivers_name, '.', diff, triggers)
      expect(dc.trigger?).to eq(expect_res)
    end
  end
end
