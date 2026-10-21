require "json"
require "digest"

module RBS
  module Shifter
    class ReleaseCheck
      def check(root:, evidence:)
        root = Pathname(root)
        catalog = Catalog.new(root: root)
        manifest_text = root.join("manifest.json").read
        manifest = JSON.parse(manifest_text)
        unresolved = manifest.fetch("unresolved", ["Coverage review is missing"])
        unless unresolved.is_a?(Array) && unresolved.empty?
          raise Error, "Publication blocked by unresolved API differences: #{Array(unresolved).join('; ')}"
        end
        report = JSON.parse(Pathname(evidence).read)
        unless report.is_a?(Hash) && report["manifest_sha256"] == Digest::SHA256.hexdigest(manifest_text) &&
            report["approved_by"].is_a?(String) && !report["approved_by"].strip.empty? &&
            report["targets"].is_a?(Hash) && report["targets"].keys.sort == catalog.targets
          raise Error, "Release evidence must identify this exact manifest, every target, and a human approver"
        end
        catalog.targets.each do |branch|
          metadata = catalog.metadata(target: branch)
          validation = metadata.fetch("validation", {})
          checks = report.fetch("targets").fetch(branch)
          unless checks.is_a?(Hash) && checks["ruby_version"] == metadata.fetch("ruby_version") &&
              checks["platform"] == "x86_64-linux" &&
              %w[runtime consumer coverage_review].all? { |key| checks[key] == true } &&
              %w[rbs reproducible].all? { |key| validation[key] == true }
            raise Error, "Release evidence is incomplete for #{branch}"
          end
          Validator.new.validate(core_root: catalog.core_root(target: branch))
        end
        true
      rescue SystemCallError, JSON::ParserError => error
        raise Error, "Cannot read release evidence: #{error.message}"
      end
    end
  end
end
