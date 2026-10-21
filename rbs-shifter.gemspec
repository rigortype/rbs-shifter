require_relative "lib/rbs/shifter/version" unless defined?(RBS::Shifter::VERSION)

Gem::Specification.new do |spec|
  spec.name = "rbs-shifter"
  spec.version = RBS::Shifter::VERSION
  spec.authors = ["RBS Shifter contributors"]
  spec.summary = "Adapt RBS core signatures to maintained older Ruby versions"
  spec.homepage = "https://github.com/rigortype/rbs-shifter"
  spec.license = "BSD-2-Clause"
  spec.required_ruby_version = ">= 3.3"
  spec.files = Dir["lib/**/*.rb", "exe/*", "rules/*.json", "data/**/*",
                   "README.md", "LICENSE", "docs/rigor-integration.md"].select { |path| File.file?(path) }.sort
  spec.bindir = "exe"
  spec.executables = ["rbs-shifter"]
  spec.require_paths = ["lib"]
  spec.add_dependency "rbs", "= 4.2.0"
end
