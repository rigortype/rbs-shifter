require_relative "test_helper"

class ReleaseCheckTest < Minitest::Test
  def setup
    @directory = Pathname(Dir.mktmpdir("shifter-release"))
    @root = @directory.join("data")
    rules = {
      "format" => 1, "source_rbs" => RBS::VERSION, "source_ruby" => "4.0.7",
      "targets" => { "3.3" => { "ruby_version" => "3.3.12", "maintenance" => "security" } },
      "unresolved" => [], "rules" => []
    }
    path = @directory.join("rules.json")
    path.write(JSON.generate(rules))
    RBS::Shifter::Generator.new(rules_path: path).generate(output: @root)
    @report = {
      "manifest_sha256" => Digest::SHA256.file(@root.join("manifest.json")).hexdigest,
      "approved_by" => "Test reviewer",
      "targets" => { "3.3" => { "ruby_version" => "3.3.12", "platform" => "x86_64-linux",
                               "runtime" => true, "consumer" => true, "coverage_review" => true } }
    }
    @evidence = @directory.join("evidence.json")
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def check
    @evidence.write(JSON.generate(@report))
    RBS::Shifter::ReleaseCheck.new.check(root: @root, evidence: @evidence)
  end

  def test_accepts_complete_human_review_evidence_for_exact_manifest
    assert check
  end

  def test_each_target_needs_runtime_consumer_and_coverage_evidence
    %w[runtime consumer coverage_review].each do |field|
      @report["targets"]["3.3"][field] = false
      assert_raises(RBS::Shifter::Error) { check }
      @report["targets"]["3.3"][field] = true
    end
  end

  def test_manifest_binding_approver_and_exact_runtime_are_required
    @report["manifest_sha256"] = "0" * 64
    assert_raises(RBS::Shifter::Error) { check }
    @report["manifest_sha256"] = Digest::SHA256.file(@root.join("manifest.json")).hexdigest
    @report["approved_by"] = " "
    assert_raises(RBS::Shifter::Error) { check }
    @report["approved_by"] = "Test reviewer"
    @report["targets"]["3.3"]["ruby_version"] = "3.3.11"
    assert_raises(RBS::Shifter::Error) { check }
  end

  def test_missing_target_evidence_and_unresolved_coverage_block_release
    @report["targets"] = {}
    assert_raises(RBS::Shifter::Error) { check }
    manifest = JSON.parse(@root.join("manifest.json").read)
    manifest["unresolved"] = ["Unreviewed API"]
    @root.join("manifest.json").write(JSON.generate(manifest))
    error = assert_raises(RBS::Shifter::Error) { check }
    assert_match(/Unreviewed API/, error.message)
  end
end
