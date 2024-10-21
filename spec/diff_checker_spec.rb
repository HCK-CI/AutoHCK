require_relative '../lib/all'

describe 'diff_checker' do
  triggers = 'spec/diff_checker_spec/triggers.yml'
  diffs = 'spec/diff_checker_spec/diff_*.txt'

  Dir[diffs].each do |diff|
    name = File.basename(diff)
    name_parts = name.split('_')

    expect_res = name_parts[4].split('.')[0] == 'pass'
    drivers_name = [name_parts[2]]
    # trigger_all
    drivers_name << '*' if name_parts[3] == 'all'

    it name.to_s do
      dc = AutoHCK::DiffChecker.new(nil, drivers_name, diff, triggers)
      expect(dc.trigger?).to eq(expect_res)
    end

    it "#{name}_exec" do
      pid = spawn("ruby bin/triggers_check --diff #{diff} --triggers #{triggers} --trigger_keys #{drivers_name.join(',')}")
      status = Process.wait2(pid)[1]
      expect(status.exitstatus).to eq(expect_res ? 0 : 1)
    end
  end
end
