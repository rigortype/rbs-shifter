# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "digest"
require "json"
require "pathname"

class CatalogTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("shifter-catalog")
    @root = Pathname(@directory).realpath / "package"
    @core = @root / "3.3/core"
    @core.mkpath
    (@core / "object.rbs").write("class Object\nend\n")
    @manifest = {
      "format" => 1,
      "source_rbs" => RBS::VERSION,
      "rules_revision" => "a" * 64,
      "targets" => {
        "3.3" => {
          "ruby_version" => "3.3.11",
          "core" => "3.3/core",
          "files" => { "object.rbs" => Digest::SHA256.file(@core / "object.rbs").hexdigest }
        }
      }
    }
    write_manifest
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_explicit_selection_and_immutable_metadata
    assert_equal ["3.3"], catalog.targets
    assert_equal @core, catalog.core_root(target: "3.3")
    assert_equal "3.3.11", catalog.metadata(target: "3.3").fetch("ruby_version")
    assert_raises(FrozenError) { catalog.metadata(target: "3.3")["files"].clear }
  end

  def test_target_branches_are_sorted
    @manifest["targets"]["3.2"] = @manifest["targets"]["3.3"].merge("ruby_version" => "3.2.11")
    write_manifest
    assert_equal ["3.2", "3.3"], catalog.targets
  end

  def test_absent_or_malformed_selection_never_falls_back
    ["3.2", "3.3.11", "", nil, 3.3, "../3.3"].each do |target|
      assert_raises(RBS::Shifter::Error) { catalog.core_root(target: target) }
    end
  end

  def test_source_parser_version_must_match
    @manifest["source_rbs"] = "0.0.0"
    write_manifest
    assert_raises(RBS::Shifter::Error) { catalog.core_root(target: "3.3") }
  end

  def test_metadata_types_and_branch_version_are_validated
    [
      ["format", "1"],
      ["source_rbs", nil],
      ["rules_revision", "unrecorded"],
      ["targets", []]
    ].each do |key, value|
      original = @manifest[key]
      @manifest[key] = value
      write_manifest
      assert_raises(RBS::Shifter::Error) { catalog }
      @manifest[key] = original
    end
    @manifest["targets"]["3.3"]["ruby_version"] = "3.2.11"
    write_manifest
    assert_raises(RBS::Shifter::Error) { catalog }
  end

  def test_modified_signature_checksum_is_rejected
    (@core / "object.rbs").write("class Changed\nend\n")
    assert_raises(RBS::Shifter::Error) { catalog.core_root(target: "3.3") }
  end

  def test_extra_nested_signature_is_rejected
    (@core / "nested").mkpath
    (@core / "nested/extra.rbs").write("class Extra\nend\n")
    assert_raises(RBS::Shifter::Error) { catalog.core_root(target: "3.3") }
  end

  def test_missing_signature_is_rejected
    (@core / "object.rbs").delete
    assert_raises(RBS::Shifter::Error) { catalog.core_root(target: "3.3") }
  end

  def test_empty_core_manifest_is_rejected
    @manifest["targets"]["3.3"]["files"] = {}
    write_manifest
    assert_raises(RBS::Shifter::Error) { catalog }
  end

  def test_empty_target_catalog_is_rejected
    @manifest["targets"] = {}
    write_manifest
    assert_raises(RBS::Shifter::Error) { catalog }
  end

  def test_directory_symlinks_cannot_hide_additional_signatures
    (@root / "extra").mkpath
    (@root / "extra/extra.rbs").write("class Extra\nend\n")
    File.symlink(@root / "extra", @core / "nested")
    assert_raises(RBS::Shifter::Error) { catalog.core_root(target: "3.3") }
  end

  def test_core_and_file_paths_cannot_escape
    ["../outside", "/tmp/outside", "3.3/../core"].each do |path|
      @manifest["targets"]["3.3"]["core"] = path
      write_manifest
      assert_raises(RBS::Shifter::Error) { catalog }
    end
    @manifest["targets"]["3.3"]["core"] = "3.3/core"
    @manifest["targets"]["3.3"]["files"] = { "../object.rbs" => "a" * 64 }
    write_manifest
    assert_raises(RBS::Shifter::Error) { catalog }
  end

  def test_signature_symlink_cannot_escape
    outside = Pathname(@directory) / "outside.rbs"
    outside.write((@core / "object.rbs").read)
    (@core / "object.rbs").delete
    File.symlink(outside, @core / "object.rbs")
    assert_raises(RBS::Shifter::Error) { catalog.core_root(target: "3.3") }
  end

  def test_core_directory_symlink_cannot_escape
    outside = Pathname(@directory) / "outside"
    FileUtils.mv(@core, outside)
    File.symlink(outside, @core)
    assert_raises(RBS::Shifter::Error) { catalog.core_root(target: "3.3") }
  end

  def test_malformed_json_is_a_catalog_error
    (@root / "manifest.json").write("{")
    assert_raises(RBS::Shifter::Error) { catalog }
  end

  # Rigor runs on Ruby 4.0 and analyses an older target (ADR-27), so the options must not depend on the
  # analyzer's runtime.
  def test_rigor_options_do_not_depend_on_the_analyzer_runtime
    [
      ["ruby", "3.3.11", "x86_64-linux"],
      ["ruby", "4.0.5", "x86_64-linux"],
      ["ruby", "4.0.5", "arm64-darwin25"],
      ["jruby", "3.3.11", "x86_64-linux"]
    ].each do |runtime|
      with_runtime(*runtime) do
        assert_equal({ core_root: @core, target_ruby: "3.3.11" }, catalog.rigor_options(target: "3.3"))
      end
    end
  end

  def test_rigor_options_refuse_an_unpackaged_target
    assert_raises(RBS::Shifter::Error) { catalog.rigor_options(target: "3.2") }
  end
  private

  def catalog
    RBS::Shifter::Catalog.new(root: @root)
  end

  def write_manifest
    (@root / "manifest.json").write(JSON.generate(@manifest))
  end

  def with_runtime(engine, version, platform)
    replacements = { RUBY_ENGINE: engine, RUBY_VERSION: version, RUBY_PLATFORM: platform }
    originals = replacements.to_h { |key, _| [key, Object.const_get(key)] }
    replacements.each do |key, value|
      Object.send(:remove_const, key)
      Object.const_set(key, value)
    end
    yield
  ensure
    originals.each do |key, value|
      Object.send(:remove_const, key)
      Object.const_set(key, value)
    end
  end
end
