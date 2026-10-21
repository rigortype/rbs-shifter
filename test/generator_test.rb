require_relative "test_helper"

class GeneratorTest < Minitest::Test
  def setup
    @directory = Pathname(Dir.mktmpdir("shifter-generator"))
    @rules = {
      "format" => 1, "source_rbs" => RBS::VERSION, "source_ruby" => "4.0.7",
      "targets" => { "3.3" => { "ruby_version" => "3.3.12", "maintenance" => "security" } },
      "unresolved" => ["Test rules do not establish API coverage"], "rules" => []
    }
    @rules_path = @directory.join("rules.json")
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def generator
    @rules_path.write(JSON.generate(@rules))
    RBS::Shifter::Generator.new(rules_path: @rules_path)
  end

  def test_generates_reproducible_complete_candidate_packages
    first = @directory.join("one")
    second = @directory.join("two")
    manifest = generator.generate(output: first)
    generator.generate(output: second)
    assert_equal first.join("manifest.json").read, second.join("manifest.json").read
    assert_equal "candidate", manifest.fetch("status")
    assert_equal ["3.3"], RBS::Shifter::Catalog.new(root: first).targets
    assert first.join("RBS-BSDL").file?
    assert first.join("RBS-COPYING").file?
    checks = manifest.fetch("targets").fetch("3.3").fetch("validation")
    assert_equal true, checks.fetch("rbs")
    assert_equal true, checks.fetch("reproducible")
    assert_equal false, checks.fetch("runtime")
    assert_equal false, checks.fetch("consumer")
    assert_equal false, checks.fetch("coverage_review")
    one = RBS::Shifter::Catalog.new(root: first).core_root(target: "3.3")
    two = RBS::Shifter::Catalog.new(root: second).core_root(target: "3.3")
    assert_equal one.glob("**/*.rbs").map { |p| p.relative_path_from(one) }, two.glob("**/*.rbs").map { |p| p.relative_path_from(two) }
  end

  def test_failure_in_second_target_leaves_no_partial_package
    @rules["targets"]["3.4"] = { "ruby_version" => "3.4.11", "maintenance" => "normal" }
    @rules["rules"] << {
      "id" => "must-fail", "targets" => ["3.4"], "file" => "array.rbs", "declaration" => "::Array",
      "action" => "remove_member", "before" => "def this_api_does_not_exist: () -> void",
      "evidence" => ["https://docs.ruby-lang.org/en/4.0/NEWS_md.html"]
    }
    destination = @directory.join("output")
    assert_raises(RBS::Shifter::Error) { generator.generate(output: destination) }
    refute destination.exist?
    assert_empty @directory.glob(".rbs-shifter-*")
  end

  def test_existing_output_is_preserved
    destination = @directory.join("output")
    destination.mkpath
    destination.join("user-file").write("keep")
    assert_raises(RBS::Shifter::Error) { generator.generate(output: destination) }
    assert_equal "keep", destination.join("user-file").read
  end

  def test_changed_parser_and_invalid_rule_configuration_fail_before_writing
    @rules["source_rbs"] = "0.0.0"
    assert_raises(RBS::Shifter::Error) { generator }
    @rules["source_rbs"] = RBS::VERSION
    @rules["targets"]["3.3"]["maintenance"] = "eol"
    assert_raises(RBS::Shifter::Error) { generator }
  end
end
