require "rubygems/version"

module RBS
  module Shifter
    class UpdateCheck
      STABLE_VERSION = /\A\d+\.\d+\.\d+\z/
      RELEASE_VERSION = /\A\d+\.\d+\.\d+(?:[.-][a-zA-Z0-9.-]+)?\z/
      BRANCH = /\A\d+\.\d+\z/
      MAINTENANCE = { "normal maintenance" => "normal", "security maintenance" => "security" }.freeze

      def initialize(config:)
        @config = config
        validate_config!
      end

      def check(rbs_version:, releases:, branches:)
        validate_version!(rbs_version, "RBS release", pattern: RELEASE_VERSION)
        latest = stable_releases(releases)
        maintained = maintained_branches(branches)
        maintained.each_key do |branch|
          raise Error, "No stable Ruby release for maintained branch #{branch}" unless latest.key?(branch)
        end
        source_branch = maintained.keys.max_by { |branch| Gem::Version.new(branch) }
        raise Error, "No maintained stable Ruby branches" unless source_branch

        updates = []
        if STABLE_VERSION.match?(rbs_version) && Gem::Version.new(rbs_version) > Gem::Version.new(@config.fetch("source_rbs"))
          updates << change("source_rbs", @config.fetch("source_rbs"), rbs_version)
        end
        source = latest.fetch(source_branch)
        if source != @config.fetch("source_ruby")
          updates << change("source_ruby", @config.fetch("source_ruby"), source)
        end
        targets = @config.fetch("targets")
        expected = maintained.reject { |branch, _| branch == source_branch }
        (targets.keys | expected.keys).sort_by { |branch| Gem::Version.new(branch) }.each do |branch|
          current = targets[branch]
          if !expected.key?(branch)
            updates << change("target_removed", current, nil, branch: branch)
          elsif !current
            updates << change("target_added", nil, { "ruby_version" => latest.fetch(branch), "maintenance" => expected.fetch(branch) }, branch: branch)
          else
            version = latest.fetch(branch)
            if version != current.fetch("ruby_version")
              updates << change("target_ruby", current.fetch("ruby_version"), version, branch: branch)
            end
            maintenance = expected.fetch(branch)
            if maintenance != current.fetch("maintenance")
              updates << change("maintenance", current.fetch("maintenance"), maintenance, branch: branch)
            end
          end
        end
        updates
      end

      private

      def change(kind, from, to, branch: nil)
        result = { "kind" => kind, "from" => from, "to" => to }
        result["branch"] = branch if branch
        result
      end

      def validate_version!(version, label, pattern: STABLE_VERSION)
        unless version.is_a?(String) && pattern.match?(version) && Gem::Version.correct?(version)
          raise Error, "Invalid #{label}: #{version.inspect}"
        end
      end

      def validate_config!
        unless @config.is_a?(Hash) && @config["targets"].is_a?(Hash)
          raise Error, "Invalid update check configuration"
        end
        validate_version!(@config["source_rbs"], "Source RBS")
        validate_version!(@config["source_ruby"], "Source Ruby")
        @config.fetch("targets").each do |branch, target|
          unless branch.is_a?(String) && BRANCH.match?(branch) && target.is_a?(Hash) && MAINTENANCE.value?(target["maintenance"])
            raise Error, "Invalid configured target #{branch.inspect}"
          end
          validate_version!(target["ruby_version"], "Target Ruby")
          unless target.fetch("ruby_version").start_with?("#{branch}.")
            raise Error, "Target Ruby does not match branch #{branch}"
          end
        end
      end

      def stable_releases(releases)
        raise Error, "Ruby releases must be a nonempty array" unless releases.is_a?(Array) && !releases.empty?

        releases.each_with_object({}) do |release, result|
          raise Error, "Invalid Ruby release entry" unless release.is_a?(Hash)

          version = release["version"]
          validate_version!(version, "Ruby release", pattern: RELEASE_VERSION)
          next unless STABLE_VERSION.match?(version)

          branch = version.split(".").first(2).join(".")
          if !result.key?(branch) || Gem::Version.new(version) > Gem::Version.new(result.fetch(branch))
            result[branch] = version
          end
        end
      end

      def maintained_branches(branches)
        raise Error, "Ruby branches must be a nonempty array" unless branches.is_a?(Array) && !branches.empty?

        seen = []
        branches.each_with_object({}) do |entry, result|
          raise Error, "Invalid Ruby branch entry" unless entry.is_a?(Hash)

          branch = entry["name"].to_s
          status = entry["status"]
          unless /\A\d+\.\d+(?:\.\d+)?\z/.match?(branch) && (MAINTENANCE.key?(status) || %w[preview eol].include?(status))
            raise Error, "Invalid Ruby branch #{entry.inspect}"
          end
          raise Error, "Duplicate Ruby branch #{branch}" if seen.include?(branch)

          seen << branch
          next unless MAINTENANCE.key?(status)
          raise Error, "Invalid maintained Ruby branch #{branch}" unless BRANCH.match?(branch)

          result[branch] = MAINTENANCE.fetch(status)
        end
      end
    end
  end
end
