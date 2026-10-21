require "rake/testtask"
require "rake/clean"
require "tmpdir"
require_relative "lib/rbs/shifter"

CLEAN.include("build")
CLOBBER.include("pkg")

Rake::TestTask.new do |task|
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
end

task default: :test

desc "Generate all candidate signature sets from the pinned RBS"
task :generate do
  ruby "-Ilib", "exe/rbs-shifter", "generate", "--output", "build/data"
end

desc "Build a development gem (not a publication approval)"
task build: :test do
  mkdir_p "pkg"
  package = File.expand_path("pkg/rbs-shifter-#{RBS::Shifter::VERSION}.gem")
  Dir.mktmpdir("rbs-shifter-package") do |directory|
    stage = Pathname(directory)
    %w[lib exe rules docs/rigor-integration.md README.md LICENSE rbs-shifter.gemspec].each do |path|
      destination = stage.join(path)
      destination.parent.mkpath
      FileUtils.cp_r(path, destination)
    end
    RBS::Shifter::Generator.new.generate(output: stage.join("data"))
    Dir.chdir(stage) { ruby "-S", "gem", "build", "rbs-shifter.gemspec", "--output", package }
  end
end
