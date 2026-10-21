# frozen_string_literal: true

require_relative "test_helper"

class CoreRulesTest < Minitest::Test
  def self.builders
    @builders ||= begin
      rules = RBS::Shifter::RuleSet.new(path: RBS::Shifter::ROOT / "rules/core.json")
      source_root = RBS::EnvironmentLoader::DEFAULT_CORE_ROOT
      files = source_root.glob("**/*.rbs").to_h do |path|
        [path.relative_path_from(source_root).to_s, path.read]
      end
      %w[3.3 3.4].to_h do |target|
        shifted = RBS::Shifter::Transformer.new(rules: rules.rules).transform(files: files, target: target)
        builder = Dir.mktmpdir("shifted-core-#{target}") do |directory|
          root = Pathname(directory)
          shifted.each do |path, source|
            destination = root / path
            destination.dirname.mkpath
            destination.write(source)
          end
          loader = RBS::EnvironmentLoader.new(core_root: root)
          environment = RBS::Environment.from_loader(loader).resolve_type_names
          RBS::DefinitionBuilder.new(env: environment)
        end
        [target, builder]
      end
    end
  end

  def test_ruby_4_additions_are_absent_and_array_find_is_inherited
    %w[3.3 3.4].each do |target|
      array = definition(target, "Array")
      refute array.methods.key?(:rfind), target
      assert_equal "::Enumerable", array.methods.fetch(:find).defined_in.to_s, target
      assert_equal array.methods.fetch(:find).method_types, array.methods.fetch(:detect).method_types, target
      math = definition(target, "Math", singleton: true)
      refute math.methods.key?(:expm1), target
      refute math.methods.key?(:log1p), target
    end
  end

  def test_ruby_34_additions_are_absent_only_from_33
    [["Array", :fetch_values, false], ["String", :append_as_bytes, false],
     ["MatchData", :bytebegin, false], ["MatchData", :byteend, false],
     ["GC", :config, true], ["Warning", :categories, true]].each do |owner, method, singleton|
      refute definition("3.3", owner, singleton: singleton).methods.key?(method), "3.3 #{owner} #{method}"
      assert definition("3.4", owner, singleton: singleton).methods.key?(method), "3.4 #{owner} #{method}"
    end
  end

  def test_strip_methods_have_no_arguments_and_preserve_return_types
    %w[3.3 3.4].each do |target|
      %i[strip strip! lstrip lstrip! rstrip rstrip!].each do |name|
        types = method_types(target, "String", name)
        assert_equal 1, types.length
        function = types.fetch(0).type
        assert_empty function.required_positionals
        assert_empty function.optional_positionals
        assert_nil function.rest_positionals
        assert_empty function.required_keywords
        assert_empty function.optional_keywords
        expected = name.to_s.end_with?("!") ? "self?" : "::String"
        assert_equal expected, function.return_type.to_s
      end
    end
  end

  def test_hash_constructor_preserves_default_and_block_but_removes_33_capacity
    %w[3.3 3.4].each do |target|
      types = method_types(target, "Hash", :initialize)
      assert_equal 2, types.length
      assert_equal ["V"], types.fetch(0).type.optional_positionals.map { |param| param.type.to_s }
      assert_nil types.fetch(0).block
      assert_equal "V", types.fetch(1).block.type.return_type.to_s
      assert_equal ["instance", "::Hash::_Key"], types.fetch(1).block.type.required_positionals.map { |param| param.type.to_s }
      types.each do |type|
        assert_equal(target == "3.4" ? [:capacity] : [], type.type.optional_keywords.keys)
      end
      constructors = method_types(target, "Hash", :new, singleton: true)
      assert_equal(target == "3.4", constructors.any? { |type| type.type.optional_keywords.key?(:capacity) })
    end
  end

  def test_exception_backtrace_location_overload_is_target_specific
    old_types = method_types("3.3", "Exception", :set_backtrace).map(&:to_s)
    new_types = method_types("3.4", "Exception", :set_backtrace).map(&:to_s)
    assert_equal 2, old_types.length
    assert old_types.any? { |type| type.include?("::String | ::Array[::String]") }
    assert old_types.any? { |type| type == "(nil) -> nil" }
    refute old_types.any? { |type| type.include?("Backtrace::Location") }
    assert_equal 3, new_types.length
    assert new_types.any? { |type| type.include?("Backtrace::Location") }
  end

  def test_raise_cause_and_backtrace_changes_compose_without_changing_kernel_aliases
    %w[3.3 3.4].each do |target|
      %w[Fiber Thread].each do |owner|
        types = method_types(target, owner, :raise)
        assert_equal 2, types.length
        types.each { |type| refute type.type.optional_keywords.key?(:cause) }
        assert_equal(target == "3.4", types.any? { |type| type.to_s.include?("Backtrace::Location") })
      end
      [false, true].each do |singleton|
        fail_types = method_types(target, "Kernel", :fail, singleton: singleton)
        raise_types = method_types(target, "Kernel", :raise, singleton: singleton)
        assert_equal fail_types.map(&:to_s), raise_types.map(&:to_s)
        assert fail_types.any? { |type| type.type.optional_keywords.key?(:cause) }
        assert_equal(target == "3.4", fail_types.any? { |type| type.to_s.include?("Backtrace::Location") })
      end
    end
  end

  private

  def definition(target, owner, singleton: false)
    name = RBS::TypeName.new(name: owner.to_sym, namespace: RBS::Namespace.root)
    builder = self.class.builders.fetch(target)
    singleton ? builder.build_singleton(name) : builder.build_instance(name)
  end

  def method_types(target, owner, name, singleton: false)
    definition(target, owner, singleton: singleton).methods.fetch(name).method_types
  end
end
