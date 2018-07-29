require 'filelock'

require './lib/project'
require './lib/client'
require './lib/studio'
require './lib/cli'

STUDIO = 'st'.freeze
CLIENT1 = 'c1'.freeze
CLIENT2 = 'c2'.freeze

cli = CLI.new
options = cli.parse(ARGV)

ENV.store 'LC_ALL', 'en_US.UTF-8'

begin
  project = Project.new(options)
  studio = Studio.new(project, STUDIO)
  client1 = Client.new(project, studio, CLIENT1)
  client2 = project.support? ? Client.new(project, studio, CLIENT2) : nil
  Filelock '/var/tmp/virthck.lock', timeout: 0 do
    studio.run
    studio.connect
    studio.create_pool
    studio.create_project
    client1.run
    client2.run if project.support?
    client1.setup_driver
    client2.setup_driver if project.support?
  end
  client1.add_target_to_project
  client1.add_support(client2) if project.support?
  client1.run_tests
rescue StandardError => e
  puts "Error during processing: #{$ERROR_INFO}"
  puts "Exception class: #{e.class}"
  puts "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
end
client1.shutdown_machine if client1
client2.shutdown_machine if client2
if studio
  studio.shutdown
  studio.close
end
