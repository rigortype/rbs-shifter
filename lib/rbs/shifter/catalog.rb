# frozen_string_literal: true

require "digest"
require "find"
require "json"
require "pathname"

module RBS
  module Shifter
    class Catalog
      BRANCH = /\A\d+\.\d+\z/
      VERSION = /\A\d+\.\d+\.\d+\z/
      CHECKSUM = /\A[0-9a-f]{64}\z/

      def initialize(root:)
        @root = Pathname(root).realpath
        manifest_path = confined_path(@root, "manifest.json")
        @manifest = JSON.parse(manifest_path.read)
        validate_manifest!
      rescue SystemCallError, JSON::ParserError => error
        raise Error, "Cannot read signature catalog: #{error.message}"
      end

      def targets
        @manifest.fetch("targets").keys.sort
      end

      def core_root(target:)
        unless target.is_a?(String) && BRANCH.match?(target)
          raise Error, "Target must be an explicit Ruby branch, such as 3.3"
        end
        entry = @manifest.fetch("targets")[target]
        raise Error, "No packaged signatures for target #{target}" unless entry
        unless RBS::VERSION == @manifest.fetch("source_rbs")
          raise Error, "Source RBS #{@manifest.fetch('source_rbs')} is required; loaded #{RBS::VERSION}"
        end

        core = confined_path(@root, entry.fetch("core"))
        raise Error, "Core is not a directory: #{core}" unless core.directory?

        actual = []
        Find.find(core.to_s) do |path|
          candidate = Pathname(path)
          if candidate.symlink? && candidate.directory?
            raise Error, "Packaged core contains a directory symlink: #{candidate}"
          end
          ensure_confined!(candidate.realpath)
          actual << candidate.relative_path_from(core).to_s if candidate.file? && candidate.extname == ".rbs"
        end
        expected = entry.fetch("files")
        unless actual.sort == expected.keys.sort
          raise Error, "Packaged core file set differs from manifest for #{target}"
        end
        expected.each do |relative, checksum|
          path = confined_path(core, relative)
          unless Digest::SHA256.file(path).hexdigest == checksum
            raise Error, "Packaged core checksum differs for #{target}/#{relative}"
          end
        end
        core
      rescue SystemCallError => error
        raise Error, "Cannot validate packaged core: #{error.message}"
      end

      def metadata(target:)
        core_root(target: target)
        @manifest.fetch("targets").fetch(target)
      end

      def rigor_options(target:)
        core = core_root(target: target)
        version = @manifest.fetch("targets").fetch(target).fetch("ruby_version")
        unless RUBY_ENGINE == "ruby" && RUBY_VERSION == version && /\Ax86_64-linux(?:-|\z)/.match?(RUBY_PLATFORM)
          raise Error, "Proposed Rigor integration requires CRuby #{version} on Linux x86_64"
        end
        { core_root: core, target_ruby: version }
      end

      private

      def validate_manifest!
        unless @manifest.is_a?(Hash) && @manifest["format"].is_a?(Integer) && @manifest["format"] == 1 &&
            @manifest["source_rbs"].is_a?(String) && VERSION.match?(@manifest["source_rbs"]) &&
            @manifest["rules_revision"].is_a?(String) && CHECKSUM.match?(@manifest["rules_revision"]) &&
            @manifest["targets"].is_a?(Hash) && !@manifest["targets"].empty?
          raise Error, "Invalid signature catalog manifest"
        end
        @manifest.fetch("targets").each do |branch, entry|
          unless BRANCH.match?(branch) && entry.is_a?(Hash) &&
              entry["ruby_version"].is_a?(String) && VERSION.match?(entry["ruby_version"]) &&
              entry["ruby_version"].start_with?("#{branch}.") &&
              relative_path?(entry["core"]) && entry["files"].is_a?(Hash) && !entry["files"].empty?
            raise Error, "Invalid signature metadata for target #{branch}"
          end
          entry.fetch("files").each do |path, checksum|
            unless relative_path?(path) && path.end_with?(".rbs") && checksum.is_a?(String) && CHECKSUM.match?(checksum)
              raise Error, "Invalid packaged core file metadata for target #{branch}"
            end
          end
        end
        deep_freeze(@manifest)
      end

      def relative_path?(path)
        path.is_a?(String) && !path.empty? && !path.include?("\0") &&
          !Pathname(path).absolute? && path.split("/", -1).none? { |part| ["", ".", ".."].include?(part) }
      end

      def confined_path(base, relative)
        raise Error, "Invalid relative catalog path" unless relative_path?(relative)

        ensure_confined!((base / relative).realpath)
      end

      def ensure_confined!(path)
        unless path == @root || path.to_s.start_with?("#{@root}/")
          raise Error, "Packaged signature path escapes catalog root: #{path}"
        end
        path
      end

      def deep_freeze(value)
        case value
        when Hash
          value.each { |key, child| key.freeze; deep_freeze(child) }
        when Array
          value.each { |child| deep_freeze(child) }
        end
        value.freeze
      end
    end
  end
end
