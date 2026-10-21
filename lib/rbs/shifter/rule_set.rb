require "json"
require "digest"

module RBS
  module Shifter
    class RuleSet
      attr_reader :config, :revision

      def initialize(path:)
        source = Pathname(path).read
        @revision = Digest::SHA256.hexdigest(source)
        @config = JSON.parse(source)
        validate!
      rescue SystemCallError, JSON::ParserError => error
        raise Error, "Cannot read shift rules: #{error.message}"
      end

      def targets
        config.fetch("targets")
      end

      def rules
        config.fetch("rules")
      end

      private

      def validate!
        unless config.is_a?(Hash) && config["format"] == 1 && config["source_rbs"] == RBS::VERSION &&
            config["source_ruby"].is_a?(String) && Catalog::VERSION.match?(config["source_ruby"]) &&
            config["targets"].is_a?(Hash) && !config["targets"].empty? && config["rules"].is_a?(Array) &&
            config["unresolved"].is_a?(Array) && config["unresolved"].all? { |item| item.is_a?(String) && !item.empty? }
          raise Error, "Invalid rules or Source RBS version; loaded RBS #{RBS::VERSION}"
        end
        targets.each do |branch, entry|
          unless branch.is_a?(String) && Catalog::BRANCH.match?(branch) && entry.is_a?(Hash) &&
              entry["ruby_version"].is_a?(String) && Catalog::VERSION.match?(entry["ruby_version"]) &&
              entry["ruby_version"].start_with?("#{branch}.") &&
              %w[normal security].include?(entry["maintenance"]) &&
              Gem::Version.new(entry["ruby_version"]) < Gem::Version.new(config.fetch("source_ruby"))
            raise Error, "Invalid or unsupported target #{branch.inspect}"
          end
        end
        ids = []
        rules.each do |rule|
          unless rule.is_a?(Hash) && rule["id"].is_a?(String) && !rule["id"].empty? &&
              rule["targets"].is_a?(Array) && !rule["targets"].empty? &&
              rule["targets"].uniq == rule["targets"] && (rule["targets"] - targets.keys).empty? &&
              relative_rbs_path?(rule["file"]) && rule["declaration"].is_a?(String) && rule["declaration"].start_with?("::") &&
              Transformer::ACTIONS.include?(rule["action"]) && rule["evidence"].is_a?(Array) &&
              !rule["evidence"].empty? && rule["evidence"].all? { |url| url.is_a?(String) && url.start_with?("https://") }
            raise Error, "Invalid shift rule #{rule.inspect}"
          end
          %w[before after].each do |key|
            required = key == "before" ? !rule["action"].start_with?("add_") : !rule["action"].start_with?("remove_")
            if required && !(rule[key].is_a?(String) && !rule[key].empty?)
              raise Error, "Rule #{rule['id']} needs #{key}"
            end
          end
          raise Error, "Duplicate rule id #{rule['id']}" if ids.include?(rule["id"])

          ids << rule["id"]
        end
      end

      def relative_rbs_path?(path)
        path.is_a?(String) && !path.include?("\0") && !Pathname(path).absolute? && path.end_with?(".rbs") &&
          path.split("/", -1).none? { |part| ["", ".", ".."].include?(part) }
      end
    end
  end
end
