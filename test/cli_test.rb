# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"

class CLITest < Minitest::Test
  EXECUTABLE = File.expand_path("../exe/rbs-shifter", __dir__)

  def setup
    @directory = Dir.mktmpdir("shifter-cli")
    @root = Pathname(@directory)
    @core = @root / "3.3/core"
    @core.mkpath
    (@core / "object.rbs").write("class Object\nend\n")
    manifest = {
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
    (@root / "manifest.json").write(JSON.generate(manifest))
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_help_and_version
    [[], ["help"], ["--help"]].each do |arguments|
      stdout, stderr, status = invoke(*arguments)
      assert status.success?, stderr
      assert_includes stdout, "Usage: rbs-shifter"
      assert_empty stderr
    end
    stdout, stderr, status = invoke("--version")
    assert status.success?, stderr
    assert_equal "#{RBS::Shifter::VERSION}\n", stdout
    assert_empty stderr
    assert File.executable?(EXECUTABLE)
  end

  def test_targets_and_path_use_verified_catalog
    stdout, stderr, status = invoke("targets", "--root", @root.to_s)
    assert status.success?, stderr
    assert_equal "3.3\n", stdout
    assert_empty stderr

    stdout, stderr, status = invoke("path", "--root=#{@root}", "--target", "3.3")
    assert status.success?, stderr
    assert_equal "#{@core.realpath}\n", stdout
    assert_empty stderr
  end

  def test_missing_required_options
    { "generate" => "output", "path" => "target", "validate" => "root", "rigor-options" => "target" }.each do |command, option|
      assert_failure [command], "Missing required option: --#{option}"
    end
  end

  def test_unknown_commands_options_and_positional_arguments
    assert_failure ["typo"], "Unknown command: typo"
    assert_failure ["targets", "--unknown"], "Unknown argument: --unknown"
    assert_failure ["targets", "junk"], "Unknown argument: junk"
    assert_failure ["path", "--tar", "3.3"], "Unknown argument: --tar"
    assert_failure ["--version", "junk"], "Unexpected argument: junk"
    assert_failure ["help", "junk"], "Unexpected argument: junk"
  end

  def test_missing_empty_and_duplicate_option_values
    assert_failure ["path", "--target"], "Missing value for --target"
    assert_failure ["path", "--target", "--root", @root.to_s], "Missing value for --target"
    assert_failure ["path", "--target="], "Missing value for --target"
    assert_failure ["path", "--target", "3.3", "--target", "3.2"], "Duplicate option: --target"
  end

  def test_unsupported_target_and_modified_catalog_fail_without_backtrace
    assert_failure ["path", "--root", @root.to_s, "--target", "3.2"], "No packaged signatures for target 3.2"
    assert_failure ["path", "--root", @root.to_s, "--target", "3.3.11"], "explicit Ruby branch"
    (@core / "object.rbs").write("class Changed\nend\n")
    assert_failure ["path", "--root", @root.to_s, "--target", "3.3"], "checksum differs"
  end

  private

  def invoke(*arguments)
    Open3.capture3(RbConfig.ruby, EXECUTABLE, *arguments)
  end

  def assert_failure(arguments, message)
    stdout, stderr, status = invoke(*arguments)
    assert_equal 1, status.exitstatus
    assert_empty stdout
    assert_includes stderr, message
    assert_equal 1, stderr.lines.length, stderr
  end
end
