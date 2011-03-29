require 'rubygems'
require 'rspec/core/rake_task'

desc "Run spec with specdoc output"

RSpec::Core::RakeTask.new do |t|
  t.pattern = 'spec/**/*_spec.rb'
  t.rspec_opts = '--color --format documentation'
end
