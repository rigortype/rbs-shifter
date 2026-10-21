require "rbs/cli"
require "stringio"

module RBS
  module Shifter
    class Validator
      def validate(core_root:)
        options = RBS::CLI::LibraryOptions.new
        options.core_root = Pathname(core_root)
        options.config_path = nil
        result = RBS::CLI::Validate.new(args: [], options: options).run
        raise Error, "RBS validation failed for #{core_root}" unless result == 0

        true
      rescue RBS::BaseError, RBS::ParsingError => error
        raise Error, "RBS validation failed: #{error.message}"
      end
    end
  end
end
