require "rbs"
require "pathname"
require_relative "shifter/version"

module RBS
  module Shifter
    class Error < StandardError; end

    ROOT = Pathname(__dir__).join("../..").expand_path.freeze
    DATA_ROOT = ROOT.join("data").freeze

    def self.core_root(target:, root: DATA_ROOT)
      Catalog.new(root: root).core_root(target: target)
    end
  end
end

require_relative "shifter/transformer"
require_relative "shifter/catalog"
require_relative "shifter/rule_set"
require_relative "shifter/validator"
require_relative "shifter/generator"
require_relative "shifter/release_check"
