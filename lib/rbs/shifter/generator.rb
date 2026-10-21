require "digest"
require "fileutils"
require "json"
require "tmpdir"

module RBS
  module Shifter
    class Generator
      def initialize(rules_path: ROOT.join("rules/core.json"), source_root: RBS::EnvironmentLoader::DEFAULT_CORE_ROOT,
                     license_root: Gem.loaded_specs.fetch("rbs").full_gem_path)
        @rule_set = RuleSet.new(path: rules_path)
        @source_root = Pathname(source_root).realpath
        @license_root = Pathname(license_root)
      rescue SystemCallError => error
        raise Error, "Cannot read Source RBS: #{error.message}"
      end

      def generate(output:)
        destination = Pathname(output).expand_path
        raise Error, "Output already exists: #{destination}" if destination.exist? || destination.symlink?
        if destination.to_s.start_with?("#{@source_root}/")
          raise Error, "Output must not be inside Source RBS"
        end
        files = source_files
        transformer = Transformer.new(rules: @rule_set.rules)
        manifest = {
          "format" => 1, "status" => "candidate", "source_rbs" => RBS::VERSION,
          "source_ruby" => @rule_set.config.fetch("source_ruby"),
          "source_digest" => Digest::SHA256.hexdigest(JSON.generate(files.transform_values { |text| Digest::SHA256.hexdigest(text) })),
          "rules_revision" => @rule_set.revision, "unresolved" => @rule_set.config.fetch("unresolved"), "targets" => {}
        }
        destination.parent.mkpath
        Dir.mktmpdir(".rbs-shifter-", destination.parent) do |temporary|
          stage = Pathname(temporary).join("data")
          stage.mkpath
          @rule_set.targets.sort.each do |branch, target|
            shifted = transformer.transform(files: files, target: branch)
            unless shifted == transformer.transform(files: files, target: branch)
              raise Error, "Generation is not deterministic for #{branch}"
            end
            core = stage.join(branch, "core")
            shifted.sort.each do |relative, text|
              path = core.join(relative)
              path.parent.mkpath
              path.write(text)
            end
            Validator.new.validate(core_root: core)
            manifest.fetch("targets")[branch] = {
              "ruby_version" => target.fetch("ruby_version"), "core" => "#{branch}/core",
              "files" => shifted.sort.to_h.transform_values { |text| Digest::SHA256.hexdigest(text) },
              "applied_rules" => @rule_set.rules.select { |rule| rule.fetch("targets").include?(branch) }.map { |rule| rule.fetch("id") },
              "validation" => { "rbs" => true, "reproducible" => true, "runtime" => false, "consumer" => false, "coverage_review" => false }
            }
          end
          %w[BSDL COPYING].each do |name|
            FileUtils.cp(@license_root.join(name), stage.join("RBS-#{name}"))
          end
          stage.join("manifest.json").write(JSON.pretty_generate(manifest) + "\n")
          Catalog.new(root: stage).targets.each { |branch| Catalog.new(root: stage).core_root(target: branch) }
          File.rename(stage, destination)
        end
        manifest
      rescue SystemCallError => error
        raise Error, "Generation failed: #{error.message}"
      end

      private

      def source_files
        paths = @source_root.glob("**/*.rbs").sort
        raise Error, "Source RBS has no core signatures" if paths.empty?

        paths.to_h do |path|
          unless path.realpath.to_s.start_with?("#{@source_root}/")
            raise Error, "Source signature escapes core root: #{path}"
          end
          [path.relative_path_from(@source_root).to_s, path.read]
        end
      end
    end
  end
end
