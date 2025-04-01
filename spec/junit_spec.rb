require 'nokogiri'
require_relative '../lib/junit/test_suites'

describe 'junit_spec' do
  s1_t1 = AutoHCK::JUnit::TestCase.new(name: 'test_name1', classname: 'test_classname', time: 1.0,
                                       file: 'test_file', line: 1)
  s1_t1.mark_failure(message: 'test_message_failure', type: 'test_type_failure',
                     description: 'test_description_failure')
  s1_t1.add_property(name: 'test_name_property1', value: 'test_value_property1',
                     description: 'test_description_property1')
  s1_t1.add_property(name: 'test_name_property2', value: 'test_value_property2')

  s1_t2 = AutoHCK::JUnit::TestCase.new(name: 'test_name2', classname: 'test_classname', time: 1.0,
                                       file: 'test_file', line: 18)
  s1_t2.mark_error(message: 'test_message_error', description: 'test_description_error')
  s1_t2.add_property(name: 'test_name_property3', description: 'test_description_property3')

  s1_t3 = AutoHCK::JUnit::TestCase.new(name: 'test_name3', classname: 'test_classname',
                                        time: 12.0, file: 'test_file',
                                       line: 88)
  s1_t3.mark_skipped(message: 'test_message_skipped')

  s1_t4 = AutoHCK::JUnit::TestCase.new(name: 'test_name4', classname: 'test_classname',
                                       time: 15.0, file: 'test_file',
                                       line: 151)
  s1_t4.add_property(name: 'test_name4_property', value: 'test_value4_property',
                     description: 'test_description4_property')

  s1_t4.add_system_output('test_system_output')

  s1 = AutoHCK::JUnit::TestSuite.new(name: 'test_suite_name', file: 'test_suite_file')
  s1.add_test_case(s1_t1)
  s1.add_test_case(s1_t2)
  s1.add_test_case(s1_t3)
  s1.add_test_case(s1_t4)
  s1.add_property(name: 'test_suite_name_property', value: 'test_suite_value_property')
  s1.add_system_output('test_suite_system_output')

  s2_t1 = AutoHCK::JUnit::TestCase.new(name: 'test2_name1', classname: 'test2_classname', time: 18.0,
                                       file: 'test2_file', line: 15)
  s2_t2 = AutoHCK::JUnit::TestCase.new(name: 'test2_name2', classname: 'test2_classname2', time: 1.0)
  s2_t2.mark_skipped(message: 'test2_message_skipped')
  s2_t2.add_system_output('test2_system_output')
  s2_t3 = AutoHCK::JUnit::TestCase.new(name: 'test2_name3', classname: 'test2_classname3', time: 87.0)
  s2_t3.add_property(name: 'test2_name3_property', value: 'test2_value3_property')

  s2 = AutoHCK::JUnit::TestSuite.new(name: 'test_suite_name2', file: 'test_suite_file2')
  s2.add_test_case(s2_t1)
  s2.add_test_case(s2_t2)
  s2.add_test_case(s2_t3)
  s2.add_system_error('test_suite_system_error')

  r = AutoHCK::JUnit::TestSuites.new(name: 'test_suites_name')
  r.add_test_suite(s1)
  r.add_test_suite(s2)

  builder = Nokogiri::XML::Builder.new do |xml|
    r.xml(xml)
  end

  it 'Generated XML is valid' do
    xml = builder.to_xml
    file_xml = File.read('spec/junit_spec.xml')
    expect(xml).to eq(file_xml)
  end
end
