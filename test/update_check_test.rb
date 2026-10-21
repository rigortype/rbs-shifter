require_relative "test_helper"
require_relative "../lib/rbs/shifter/update_check"

class UpdateCheckTest < Minitest::Test
  def setup
    @config = {
      "source_rbs" => "4.2.0", "source_ruby" => "4.0.7",
      "targets" => {
        "3.3" => { "ruby_version" => "3.3.12", "maintenance" => "security" },
        "3.4" => { "ruby_version" => "3.4.11", "maintenance" => "normal" }
      }
    }
    @releases = %w[4.1.0-preview1 4.0.7 4.0.6 3.4.11 3.4.9 3.3.12 3.3.9 3.2.11 1.8.7-p374].map { |version| { "version" => version } }
    @branches = [
      { "name" => 4.1, "status" => "preview" },
      { "name" => 4.0, "status" => "normal maintenance" },
      { "name" => 3.4, "status" => "normal maintenance" },
      { "name" => 3.3, "status" => "security maintenance" },
      { "name" => 3.2, "status" => "eol" },
      { "name" => "1.8.7", "status" => "eol" }
    ]
  end

  def check(rbs_version: "4.2.0", releases: @releases, branches: @branches)
    RBS::Shifter::UpdateCheck.new(config: @config).check(rbs_version: rbs_version, releases: releases, branches: branches)
  end

  def test_unchanged_snapshot_ignores_preview_and_eol
    assert_empty check
  end

  def test_detects_only_newer_stable_rbs
    assert_equal [{ "kind" => "source_rbs", "from" => "4.2.0", "to" => "4.10.0" }], check(rbs_version: "4.10.0")
    assert_empty check(rbs_version: "4.1.0")
    assert_empty check(rbs_version: "4.3.0.pre.1")
  end

  def test_detects_latest_patch_using_numeric_version_order
    @releases.concat(%w[3.4.12 3.4.20 3.4.13 3.3.13 3.3.14-rc1].map { |version| { "version" => version } })
    assert_equal [
      { "kind" => "target_ruby", "from" => "3.3.12", "to" => "3.3.13", "branch" => "3.3" },
      { "kind" => "target_ruby", "from" => "3.4.11", "to" => "3.4.20", "branch" => "3.4" }
    ], check
  end

  def test_detects_source_ruby_patch_change
    @releases << { "version" => "4.0.8" }
    assert_equal [{ "kind" => "source_ruby", "from" => "4.0.7", "to" => "4.0.8" }], check
  end

  def test_new_stable_branch_moves_source_and_adds_previous_source_as_target
    @branches.first["status"] = "normal maintenance"
    @releases << { "version" => "4.1.0" }
    assert_equal [
      { "kind" => "source_ruby", "from" => "4.0.7", "to" => "4.1.0" },
      { "kind" => "target_added", "from" => nil, "to" => { "ruby_version" => "4.0.7", "maintenance" => "normal" }, "branch" => "4.0" }
    ], check
  end

  def test_eol_removes_existing_target
    @branches.find { |entry| entry["name"] == 3.3 }["status"] = "eol"
    assert_equal [{ "kind" => "target_removed", "from" => @config["targets"]["3.3"], "to" => nil, "branch" => "3.3" }], check
  end

  def test_detects_maintenance_status_change
    @branches.find { |entry| entry["name"] == 3.4 }["status"] = "security maintenance"
    assert_equal [{ "kind" => "maintenance", "from" => "normal", "to" => "security", "branch" => "3.4" }], check
  end

  def test_missing_stable_release_for_maintained_branch_is_an_error
    @releases.reject! { |release| release["version"].start_with?("3.3.") }
    error = assert_raises(RBS::Shifter::Error) { check }
    assert_match(/No stable Ruby release for maintained branch 3.3/, error.message)
  end

  def test_no_maintained_branches_is_an_error
    @branches.each { |branch| branch["status"] = "eol" }
    assert_raises(RBS::Shifter::Error) { check }
  end

  def test_rejects_malformed_upstream_versions_and_collections
    [nil, "", "banana", 4.2, "4.2", "4.2.0\n"].each do |version|
      assert_raises(RBS::Shifter::Error) { check(rbs_version: version) }
    end
    [nil, {}, [], [nil], [{}], [{ "version" => "broken" }]].each do |releases|
      assert_raises(RBS::Shifter::Error) { check(releases: releases) }
    end
    [nil, {}, [], [nil], [{}], [{ "name" => 4.0, "status" => "unknown" }]].each do |branches|
      assert_raises(RBS::Shifter::Error) { check(branches: branches) }
    end
  end

  def test_rejects_duplicate_branches
    @branches << { "name" => "3.4", "status" => "security maintenance" }
    assert_raises(RBS::Shifter::Error) { check }
  end

  def test_rejects_invalid_configuration
    [nil, {}, { "targets" => [] }, @config.merge("source_ruby" => "4.1.0-preview1"),
     @config.merge("source_rbs" => nil), @config.merge("targets" => { "3.4" => nil }),
     @config.merge("targets" => { "3.4" => { "ruby_version" => "3.3.12", "maintenance" => "normal" } })].each do |config|
      assert_raises(RBS::Shifter::Error) { RBS::Shifter::UpdateCheck.new(config: config) }
    end
  end

  def test_inputs_are_not_mutated
    before = Marshal.dump([@config, @releases, @branches])
    check(rbs_version: "4.3.0")
    assert_equal before, Marshal.dump([@config, @releases, @branches])
  end
end
