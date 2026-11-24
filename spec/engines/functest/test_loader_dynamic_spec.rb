# frozen_string_literal: true

require_relative '../../../lib/all'
require_relative '../../../lib/engines/functest/test_loader'
require 'tmpdir'

describe AutoHCK::Functest::TestLoader do
  let(:logger) { MonoLogger.new(File::NULL) }
  let(:project) { instance_double(AutoHCK::Project, logger: logger) }

  def write_case(dir, name, json_body, ruby_body: nil)
    cases_dir = File.join(dir, 'cases', File.dirname(name))
    FileUtils.mkdir_p(cases_dir)
    base = File.join(dir, 'cases', name)
    File.write("#{base}.json", json_body)
    File.write("#{base}.rb", ruby_body) if ruby_body
  end

  describe '#load_test with dynamic cases' do
    it 'attaches dynamic_path when dynamic is true and the sibling .rb exists' do
      Dir.mktmpdir('functest_dynamic') do |dir|
        write_case(
          dir,
          'qmp/sample_dynamic',
          <<~JSON,
            {
              "name": "sample_dynamic",
              "dynamic": true
            }
          JSON
          ruby_body: <<~RUBY
            module AutoHCK
              module Functest
                module DynamicTests
                  def self.sample_dynamic
                    Class.new(AutoHCK::Functest::DynamicTest)
                  end
                end
              end
            end
          RUBY
        )

        loader = described_class.new(project, dir)
        test = loader.load_test('qmp/sample_dynamic')

        expect(test.dynamic).to be(true)
        expect(test.dynamic_path).to eq(File.expand_path('cases/qmp/sample_dynamic.rb', dir))
        expect(test.test_steps).to eq([])
      end
    end

    it 'raises when dynamic is true but the sibling .rb is missing' do
      Dir.mktmpdir('functest_dynamic') do |dir|
        write_case(
          dir,
          'missing_rb',
          <<~JSON
            {
              "name": "missing_rb",
              "dynamic": true
            }
          JSON
        )

        loader = described_class.new(project, dir)
        expect { loader.load_test('missing_rb') }.to raise_error(
          AutoHCK::InvalidConfigFile, /requires .*missing_rb\.rb/
        )
      end
    end

    it 'leaves dynamic false for ordinary JSON cases' do
      Dir.mktmpdir('functest_dynamic') do |dir|
        write_case(
          dir,
          'plain',
          <<~JSON
            {
              "name": "plain",
              "test_steps": [
                { "desc": "noop", "host_run": "true" }
              ]
            }
          JSON
        )

        loader = described_class.new(project, dir)
        test = loader.load_test('plain')

        expect(test.dynamic).to be(false)
        expect(test.dynamic_path).to be_nil
      end
    end
  end

  describe '.load_dynamic_test_class' do
    it 'returns the DynamicTest subclass from DynamicTests.<basename>' do
      Dir.mktmpdir('functest_dynamic') do |dir|
        write_case(
          dir,
          'factory_ok',
          <<~JSON,
            { "name": "factory_ok", "dynamic": true }
          JSON
          ruby_body: <<~RUBY
            module AutoHCK
              module Functest
                module DynamicTests
                  def self.factory_ok
                    Class.new(AutoHCK::Functest::DynamicTest)
                  end
                end
              end
            end
          RUBY
        )

        loader = described_class.new(project, dir)
        test = loader.load_test('factory_ok')
        klass = described_class.load_dynamic_test_class(test)

        expect(klass).to be < AutoHCK::Functest::DynamicTest
      end
    end

    it 'raises when the factory method is missing' do
      Dir.mktmpdir('functest_dynamic') do |dir|
        write_case(
          dir,
          'no_factory',
          <<~JSON,
            { "name": "no_factory", "dynamic": true }
          JSON
          ruby_body: "# no DynamicTests.no_factory defined\n"
        )

        loader = described_class.new(project, dir)
        test = loader.load_test('no_factory')
        expect { described_class.load_dynamic_test_class(test) }.to raise_error(
          AutoHCK::InvalidConfigFile, /DynamicTests\.no_factory not defined/
        )
      end
    end
  end
end
