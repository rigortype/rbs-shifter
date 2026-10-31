# frozen_string_literal: true

require "json"

module RBS
  module Shifter
    class CLI
      HELP = <<~TEXT.freeze
        Usage: rbs-shifter COMMAND [OPTIONS]

        Commands:
          generate --output DIR [--rules FILE]
          targets [--root DIR]
          path --target BRANCH [--root DIR]
          validate --root DIR [--target BRANCH]
          rigor-options --target BRANCH [--root DIR]
          release-check --root DIR --evidence FILE
          help

        Options:
          --help       Show this help
          --version    Show the version

        Targets are explicit Ruby branches, such as 3.3.
        rigor-options emits Rigor's core_root and target_ruby values for a branch.
      TEXT

      def initialize(stdout: $stdout, stderr: $stderr)
        @stdout = stdout
        @stderr = stderr
      end

      def run(argv)
        arguments = argv.dup
        command = arguments.shift
        case command
        when nil, "help", "--help"
          reject_arguments!(arguments)
          @stdout.puts HELP
        when "--version"
          reject_arguments!(arguments)
          @stdout.puts VERSION
        when "generate"
          options = parse_options(arguments, allowed: %w[output rules], required: %w[output])
          output = Pathname(options.fetch("output")).expand_path
          rules = Pathname(options.fetch("rules", ROOT.join("rules/core.json")))
          Generator.new(rules_path: rules).generate(output: output)
          @stdout.puts output
        when "targets"
          options = parse_options(arguments, allowed: %w[root])
          @stdout.puts catalog(options).targets
        when "path", "rigor-options"
          options = parse_options(arguments, allowed: %w[root target], required: %w[target])
          selection = catalog(options)
          target = options.fetch("target")
          if command == "path"
            @stdout.puts selection.core_root(target: target)
          else
            result = selection.rigor_options(target: target)
            @stdout.puts JSON.generate(result.merge(core_root: result.fetch(:core_root).to_s))
          end
        when "validate"
          options = parse_options(arguments, allowed: %w[root target], required: %w[root])
          selection = catalog(options)
          targets = options.key?("target") ? [options.fetch("target")] : selection.targets
          targets.each do |target|
            Validator.new.validate(core_root: selection.core_root(target: target))
          end
          @stdout.puts "Validated #{targets.length} target(s): #{targets.join(', ')}"
        when "release-check"
          options = parse_options(arguments, allowed: %w[root evidence], required: %w[root evidence])
          ReleaseCheck.new.check(root: options.fetch("root"), evidence: options.fetch("evidence"))
          @stdout.puts "Release evidence accepted for all targets"
        else
          raise Error, "Unknown command: #{command}"
        end
        0
      rescue Error => error
        @stderr.puts "rbs-shifter: #{error.message}"
        1
      end

      private

      def catalog(options)
        Catalog.new(root: Pathname(options.fetch("root", DATA_ROOT)))
      end

      def reject_arguments!(arguments)
        raise Error, "Unexpected argument: #{arguments.first}" unless arguments.empty?
      end

      def parse_options(arguments, allowed:, required: [])
        options = {}
        until arguments.empty?
          argument = arguments.shift
          flag, value = argument.split("=", 2)
          name = flag.delete_prefix("--")
          unless flag.start_with?("--") && allowed.include?(name)
            raise Error, "Unknown argument: #{argument}"
          end
          raise Error, "Duplicate option: #{flag}" if options.key?(name)

          value ||= arguments.shift unless arguments.first&.start_with?("--")
          raise Error, "Missing value for #{flag}" if value.nil? || value.empty?

          options[name] = value
        end
        required.each do |name|
          raise Error, "Missing required option: --#{name}" unless options.key?(name)
        end
        options
      end
    end
  end
end
