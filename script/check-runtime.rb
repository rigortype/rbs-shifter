#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "digest"
require "pathname"
require "timeout"

class RuntimeChecks
  class Failure < StandardError; end

  def initialize(branch)
    @branch = branch
  end

  def assert(condition, message)
    raise Failure, message unless condition
  end

  def rejects(error_class)
    begin
      yield
    rescue error_class
      return
    end
    raise Failure, "expected #{error_class}"
  end

  def captured
    begin
      yield
    rescue StandardError => error
      return error
    end
    raise Failure, "expected an exception"
  end

  def locations
    caller_locations(0, 1)
  end

  def absent(receiver, name)
    assert(!receiver.respond_to?(name, true), "#{receiver.class} unexpectedly responds to #{name}")
    rejects(NoMethodError) { receiver.public_send(name) }
  end

  def introduced(receiver, name)
    if @branch == "3.3"
      absent(receiver, name)
    else
      assert(receiver.respond_to?(name), "missing #{name}")
      yield
    end
  end

  def check_backtrace(error, trace)
    assert(error.instance_of?(RuntimeError) && error.message == "runtime probe", "wrong delivered exception: #{error.inspect}")
    expected = trace.map(&:to_s)
    assert(error.backtrace == expected, "backtrace differs")
    if trace.first.is_a?(Thread::Backtrace::Location)
      fields = ->(frames) { frames.map { |frame| [frame.path, frame.absolute_path, frame.lineno, frame.label, frame.base_label] } }
      actual = error.backtrace_locations
      assert(actual.is_a?(Array) && fields.call(actual) == fields.call(trace), "backtrace locations differ")
    end
  end

  def with_fiber
    fiber = Fiber.new do
      begin
        Fiber.yield(:ready)
      rescue StandardError => error
        error
      end
    end
    assert(fiber.resume == :ready, "fiber did not become ready")
    yield fiber
  ensure
    fiber.resume if fiber && fiber.alive?
  end

  def with_thread
    ready = Queue.new
    gate = Queue.new
    delivered = Queue.new
    thread = Thread.new do
      begin
        ready << true
        gate.pop
      rescue StandardError => error
        delivered << error
      end
    end
    thread.report_on_exception = false
    Timeout.timeout(5) do
      ready.pop
      yield thread, delivered
    end
  ensure
    if thread
      thread.kill
      thread.join
    end
  end

  def fiber_cause
    with_fiber do |fiber|
      rejects(ArgumentError) { fiber.raise(RuntimeError, "runtime probe", ["probe:1"], cause: RuntimeError.new("cause")) }
      check_backtrace(fiber.raise(RuntimeError, "runtime probe", ["probe:1"]), ["probe:1"])
    end
  end

  def fiber_backtrace
    trace = locations
    with_fiber do |fiber|
      if @branch == "3.3"
        rejects(TypeError) { fiber.raise(RuntimeError, "runtime probe", trace) }
        check_backtrace(fiber.raise(RuntimeError, "runtime probe", ["probe:1"]), ["probe:1"])
      else
        check_backtrace(fiber.raise(RuntimeError, "runtime probe", trace), trace)
      end
    end
  end

  def thread_cause
    with_thread do |thread, delivered|
      rejects(ArgumentError) { thread.raise(RuntimeError, "runtime probe", ["probe:1"], cause: RuntimeError.new("cause")) }
      thread.raise(RuntimeError, "runtime probe", ["probe:1"])
      check_backtrace(delivered.pop, ["probe:1"])
    end
  end

  def thread_backtrace
    trace = locations
    with_thread do |thread, delivered|
      if @branch == "3.3"
        rejects(TypeError) { thread.raise(RuntimeError, "runtime probe", trace) }
        thread.raise(RuntimeError, "runtime probe", ["probe:1"])
        check_backtrace(delivered.pop, ["probe:1"])
      else
        thread.raise(RuntimeError, "runtime probe", trace)
        check_backtrace(delivered.pop, trace)
      end
    end
  end

  def kernel_backtrace
    trace = locations
    [Kernel, Object.new].each do |receiver|
      [:raise, :fail].each do |name|
        cause = RuntimeError.new("cause")
        error = captured { receiver.__send__(name, RuntimeError, "runtime probe", ["probe:1"], cause: cause) }
        check_backtrace(error, ["probe:1"])
        assert(error.cause.equal?(cause), "Kernel #{name} lost explicit cause")
        if @branch == "3.3"
          rejects(TypeError) { receiver.__send__(name, RuntimeError, "runtime probe", trace) }
        else
          error = captured { receiver.__send__(name, RuntimeError, "runtime probe", trace, cause: cause) }
          check_backtrace(error, trace)
          assert(error.cause.equal?(cause), "Kernel #{name} lost explicit cause with locations")
        end
      end
    end
  end

  def probes
    checks = {
      "array.rfind.before_4.0" => -> { absent([], :rfind) },
      "array.find.before_4.0" => -> {
        assert([].method(:find).owner == Enumerable, "Array#find is not inherited from Enumerable")
        assert([1, 2, 3].find { |value| value.even? } == 2, "Array#find returned wrong value")
        assert([].find(-> { :missing }) { true } == :missing, "Array#find lost fallback")
        assert([].find.is_a?(Enumerator), "Array#find without block is not an Enumerator")
      },
      "math.expm1.before_4.0" => -> { absent(Math, :expm1) },
      "math.log1p.before_4.0" => -> { absent(Math, :log1p) },
      "array.fetch_values.before_3.4" => -> {
        introduced([], :fetch_values) do
          assert([10, 20].fetch_values(1, 0) == [20, 10], "fetch_values returned wrong values")
          assert([10].fetch_values(0, 2) { |index| index * 3 } == [10, 6], "fetch_values fallback differs")
          rejects(IndexError) { [].fetch_values(0) }
        end
      },
      "string.append_as_bytes.before_3.4" => -> {
        introduced("", :append_as_bytes) do
          value = +"a"
          assert(value.append_as_bytes(0xff, "b").equal?(value), "append_as_bytes did not return receiver")
          assert(value.bytes == [97, 255, 98], "append_as_bytes changed byte values")
          assert(value.encoding == Encoding::UTF_8, "append_as_bytes changed encoding")
        end
      },
      "match_data.bytebegin.before_3.4" => -> {
        match = /(?<letter>\u00e9)(?<optional>z)?/.match("\u3042\u00e9")
        introduced(match, :bytebegin) do
          assert(match.bytebegin(:letter) == 3 && match.bytebegin(2).nil?, "bytebegin offsets differ")
        end
      },
      "match_data.byteend.before_3.4" => -> {
        match = /(?<letter>\u00e9)(?<optional>z)?/.match("\u3042\u00e9")
        introduced(match, :byteend) do
          assert(match.byteend(:letter) == 5 && match.byteend(2).nil?, "byteend offsets differ")
        end
      },
      "gc.config.before_3.4" => -> {
        introduced(GC, :config) do
          assert(GC.config.is_a?(Hash) && GC.config({}).is_a?(Hash), "GC.config did not return Hash")
        end
      },
      "warning.categories.before_3.4" => -> {
        introduced(Warning, :categories) do
          categories = Warning.categories
          assert(categories.is_a?(Array) && categories.include?(:deprecated) && categories.all? { |value| value.is_a?(Symbol) }, "Warning.categories differs")
        end
      },
      "hash.initialize.before_3.4" => -> {
        assert(Hash.new(:missing)[:key] == :missing, "Hash default differs")
        assert(Hash.new { |hash, key| hash[key] = key.to_s }[:key] == "key", "Hash default block differs")
        if @branch == "3.3"
          assert(Hash.new(capacity: 4)[:key] == { capacity: 4 }, "3.3 keywords must become the default Hash")
          rejects(ArgumentError) { Hash.new(:missing, capacity: 4) }
        else
          hash = Hash.new(:missing, capacity: 4)
          hash[:present] = 1
          assert(hash[:missing] == :missing && hash[:present] == 1, "capacity constructor lost default or entries")
          assert(Hash.new(capacity: 4).default.nil?, "capacity became default value")
          assert(Hash.new(capacity: 4) { |result, key| result[key] = key }[:key] == :key, "capacity constructor lost block")
          assert(Hash.new(capacity: -1).default.nil?, "negative capacity became a default value")
        end
      },
      "exception.set_backtrace.before_3.4" => -> {
        error = RuntimeError.new("runtime probe")
        assert(error.set_backtrace("probe:1") == ["probe:1"], "string backtrace differs")
        assert(error.set_backtrace(["probe:2"]) == ["probe:2"], "array backtrace differs")
        assert(error.set_backtrace(nil).nil? && error.backtrace.nil?, "nil backtrace differs")
        trace = locations
        if @branch == "3.3"
          rejects(TypeError) { error.set_backtrace(trace) }
        else
          assert(error.set_backtrace(trace) == trace, "set_backtrace did not return locations")
          check_backtrace(error, trace)
        end
      },
      "fiber.raise.cause_before_4.0" => -> { fiber_cause },
      "fiber.raise.backtrace_before_3.4" => -> { fiber_backtrace },
      "thread.raise.cause_before_4.0" => -> { thread_cause },
      "thread.raise.backtrace_before_3.4" => -> { thread_backtrace },
      "kernel.fail.before_3.4" => -> { kernel_backtrace }
    }
    { "strip" => "value", "lstrip" => "value \t", "rstrip" => " \tvalue" }.each do |name, expected|
      [false, true].each do |bang|
        method = "#{name}#{bang ? '!' : ''}"
        id = "string.#{name}#{bang ? '_' : ''}.before_4.0"
        checks[id] = -> {
          value = +" \tvalue \t"
          result = value.public_send(method)
          assert(result == expected, "#{method} returned #{result.inspect}")
          if bang
            assert(result.equal?(value), "#{method} did not return receiver")
            assert(value.public_send(method).nil?, "#{method} should return nil when unchanged")
          else
            assert(value == " \tvalue \t", "#{method} mutated receiver")
          end
          rejects(ArgumentError) { value.public_send(method, "x") }
        }
      end
    end
    checks
  end
end

begin
  raise RuntimeChecks::Failure, "usage: ruby script/check-runtime.rb ROOT BRANCH" unless ARGV.length == 2
  root = Pathname(ARGV.fetch(0))
  branch = ARGV.fetch(1)
  manifest_text = root.join("manifest.json").read
  manifest = JSON.parse(manifest_text)
  target = manifest.fetch("targets").fetch(branch)
  version = target.fetch("ruby_version")
  unless %w[3.3 3.4].include?(branch) && version.is_a?(String) && /\A#{Regexp.escape(branch)}\.\d+\z/.match?(version)
    raise RuntimeChecks::Failure, "unsupported manifest target #{branch.inspect}: #{version.inspect}"
  end
  unless RUBY_ENGINE == "ruby" && RUBY_VERSION == version && /\Ax86_64-linux(?:-|\z)/.match?(RUBY_PLATFORM)
    raise RuntimeChecks::Failure, "unsupported runtime: need CRuby #{version} on Linux x86_64; got #{RUBY_ENGINE} #{RUBY_VERSION} #{RUBY_PLATFORM}"
  end
  rules_text = Pathname(__dir__).join("../rules/core.json").read
  rules = JSON.parse(rules_text)
  unless manifest.fetch("rules_revision") == Digest::SHA256.hexdigest(rules_text) && rules.fetch("targets").fetch(branch).fetch("ruby_version") == version
    raise RuntimeChecks::Failure, "manifest does not match bundled rules and target version"
  end
  active = rules.fetch("rules").select { |rule| rule.fetch("targets").include?(branch) }.map { |rule| rule.fetch("id") }
  unless target.fetch("applied_rules") == active && active.uniq == active && !active.empty?
    raise RuntimeChecks::Failure, "manifest applied_rules differ from active bundled rules"
  end
  probes = RuntimeChecks.new(branch).probes
  missing = rules.fetch("rules").map { |rule| rule.fetch("id") } - probes.keys
  raise RuntimeChecks::Failure, "missing runtime probes: #{missing.join(', ')}" unless missing.empty?
  results = probes.map do |id, probe|
    begin
      Timeout.timeout(10) { probe.call }
      { "id" => id, "passed" => true }
    rescue StandardError => error
      warn "#{id}: #{error.class}: #{error.message}"
      { "id" => id, "passed" => false, "error" => "#{error.class}: #{error.message}" }
    end
  end
  passed = results.all? { |result| result.fetch("passed") }
  puts JSON.pretty_generate({
    "manifest_sha256" => Digest::SHA256.hexdigest(manifest_text),
    "target" => branch, "ruby_version" => RUBY_VERSION, "platform" => "x86_64-linux",
    "ruby_platform" => RUBY_PLATFORM, "checked_rules" => active,
    "probes" => results, "runtime" => passed, "consumer" => false, "coverage_review" => false
  })
  exit(passed ? 0 : 1)
rescue StandardError => error
  warn "runtime check failed: #{error.class}: #{error.message}"
  exit 1
end
