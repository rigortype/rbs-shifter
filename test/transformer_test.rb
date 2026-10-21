# frozen_string_literal: true

require_relative "test_helper"

class TransformerTest < Minitest::Test
  def rule(action, **options)
    {
      "id" => "test-shift",
      "targets" => ["3.3"],
      "file" => "array.rbs",
      "declaration" => "::Array",
      "action" => action,
      "evidence" => ["https://docs.ruby-lang.org/en/3.3/Array.html"]
    }.merge(options.transform_keys(&:to_s))
  end

  def transform(source, *rules)
    RBS::Shifter::Transformer.new(rules: rules).transform(files: { "array.rbs" => source }, target: "3.3").fetch("array.rbs")
  end

  def parse(source)
    RBS::Parser.parse_signature(source).last
  end

  def test_remove_member_preserves_singleton_method_and_unrelated_comments
    source = <<~RBS
      use Enumerable as Collection
      # array docs
      class Array
        # new method
        def modern: () -> void
        # retained docs
        def self.modern: () -> Integer
      end
    RBS
    output = transform(source, rule("remove_member", before: "def modern: () -> void"))
    assert_equal [:singleton], parse(output).first.members.map(&:kind)
    assert_includes output, "use Enumerable as Collection"
    assert_includes output, "# array docs"
    assert_includes output, "# retained docs"
  end

  def test_replace_complete_overloads_in_generic_owner
    source = <<~RBS
      class Array[Elem]
        def fetch: (Integer) -> Elem
                 | (Integer, Elem) -> Elem
      end
    RBS
    output = transform(source, rule("replace_member",
                                   before: "def fetch: (Integer)->Elem | (Integer,Elem)->Elem",
                                   after: "def fetch: (Integer) -> Elem"))
    method = parse(output).first.members.first
    assert_equal 1, method.overloads.length
    assert_instance_of RBS::Types::Variable, method.overloads.first.method_type.type.return_type
  end

  def test_restore_removed_member
    output = transform("class Array\nend\n", rule("add_member", after: "def old: () -> String"))
    assert_equal :old, parse(output).first.members.first.name
  end

  def test_replace_declaration_changes_inheritance
    output = transform("class Array < Object\nend\n",
                       rule("replace_declaration", before: "class Array < Object\nend",
                            after: "class Array < BasicObject\nend"))
    assert_equal "BasicObject", parse(output).first.super_class.name.to_s
  end

  def test_nested_namespace_and_member_alias
    source = "module Outer\nclass Array\nalias old current\nend\nend\n"
    output = transform(source, rule("replace_member", declaration: "::Outer::Array",
                                   before: "alias old current", after: "alias old previous"))
    member = parse(output).first.members.first.members.first
    assert_equal :previous, member.old_name
  end

  def test_qualified_declaration_and_type_alias
    source = "class Outer::Array\nend\ntype scalar = Integer | String\n"
    output = transform(source, rule("remove_declaration", declaration: "::scalar",
                                   before: "type scalar = Integer | String"))
    assert_equal ["Outer::Array"], parse(output).map { |node| node.name.to_s }
  end

  def test_class_alias_declaration
    output = transform("class Array = List\n", rule("replace_declaration",
                                                   before: "class Array = List",
                                                   after: "class Array = Sequence"))
    assert_equal "Sequence", parse(output).first.old_name.to_s
  end

  def test_add_nested_declaration
    output = transform("module Outer\nend\n", rule("add_declaration", declaration: "::Outer::Array",
                                                  after: "class Array\nend"))
    assert_equal "Array", parse(output).first.members.first.name.to_s
  end

  def test_add_top_level_declaration
    output = transform("class Other\nend\n", rule("add_declaration", after: "class Array\nend"))
    assert_equal %w[Other Array], parse(output).map { |node| node.name.to_s }
  end

  def test_changed_member_precondition_fails
    error = assert_raises(RBS::Shifter::Error) do
      transform("class Array\ndef modern: () -> Integer\nend",
                rule("remove_member", before: "def modern: () -> void"))
    end
    assert_match(/precondition/, error.message)
  end

  def test_changed_declaration_precondition_fails
    assert_raises(RBS::Shifter::Error) do
      transform("class Array < Object\nend",
                rule("remove_declaration", before: "class Array < BasicObject\nend"))
    end
  end

  def test_partial_overload_precondition_fails
    assert_raises(RBS::Shifter::Error) do
      transform("class Array\ndef fetch: () -> Integer | (Integer) -> String\nend",
                rule("remove_member", before: "def fetch: () -> Integer"))
    end
  end

  def test_missing_file_owner_and_member_fail
    [
      rule("remove_member", file: "missing.rbs", before: "def absent: () -> void"),
      rule("remove_member", declaration: "::Missing", before: "def absent: () -> void"),
      rule("remove_member", before: "def absent: () -> void")
    ].each do |shift|
      assert_raises(RBS::Shifter::Error) { transform("class Array\nend", shift) }
    end
  end

  def test_ambiguous_owner_and_member_fail
    assert_raises(RBS::Shifter::Error) do
      transform("class Array\nend\nclass Array\nend",
                rule("add_member", after: "def old: () -> void"))
    end
    assert_raises(RBS::Shifter::Error) do
      transform("class Array\ndef old: () -> void\ndef old: () -> void\nend",
                rule("remove_member", before: "def old: () -> void"))
    end
  end

  def test_duplicate_member_identities_fail
    ["def old: () -> Integer", "alias old other", "attr_reader old: Integer", "def self?.old: () -> Integer"].each do |existing|
      assert_raises(RBS::Shifter::Error) do
        transform("class Array\n#{existing}\nend", rule("add_member", after: "def old: () -> void"))
      end
    end
  end

  def test_attribute_writer_identity_conflicts_with_setter
    assert_raises(RBS::Shifter::Error) do
      transform("class Array\nattr_accessor old: Integer\nend",
                rule("add_member", after: "def old=: (Integer) -> Integer"))
    end
  end

  def test_instance_and_singleton_additions_are_distinct
    output = transform("class Array\ndef old: () -> void\nend",
                       rule("add_member", after: "def self.old: () -> void"))
    assert_equal %i[instance singleton], parse(output).first.members.map(&:kind)
  end

  def test_duplicate_declaration_name_fails
    assert_raises(RBS::Shifter::Error) do
      transform("class Array\nend", rule("add_declaration", after: "class Array < Object\nend"))
    end
  end

  def test_replacement_cannot_collide_with_another_member
    assert_raises(RBS::Shifter::Error) do
      transform("class Array\ndef first: () -> void\ndef second: () -> void\nend",
                rule("replace_member", before: "def first: () -> void", after: "def second: () -> String"))
    end
  end

  def test_declaration_replacement_cannot_change_name
    assert_raises(RBS::Shifter::Error) do
      transform("class Array\nend", rule("replace_declaration", before: "class Array\nend",
                                       after: "class Other\nend"))
    end
  end

  def test_invalid_and_multiple_snippets_fail
    ["def broken:", "def one: () -> void\ndef two: () -> void", "class Nested\nend"].each do |snippet|
      assert_raises(RBS::Shifter::Error) do
        transform("class Array\nend", rule("add_member", after: snippet))
      end
    end
    assert_raises(RBS::Shifter::Error) do
      transform("", rule("add_declaration", after: "class Array\nend\nclass Other\nend"))
    end
  end

  def test_unsupported_action_fails
    assert_raises(RBS::Shifter::Error) { transform("class Array\nend", rule("rewrite")) }
  end

  def test_inactive_target_leaves_exact_source_unchanged
    source = "class Array\n\nend\n"
    assert_equal source, transform(source, rule("rewrite", targets: ["3.4"]))
  end

  def test_deterministic_output_and_no_input_mutation
    source = "class Array\ndef modern: () -> void\nend\n".freeze
    files = { "array.rbs" => source, "untouched.rbs" => "class Other\nend\n".freeze }.freeze
    rules = [rule("remove_member", before: "def modern: () -> void").freeze].freeze
    transformer = RBS::Shifter::Transformer.new(rules: rules)
    first = transformer.transform(files: files, target: "3.3")
    assert_equal first, transformer.transform(files: files, target: "3.3")
    assert_equal source, files.fetch("array.rbs")
    assert_equal files.fetch("untouched.rbs"), first.fetch("untouched.rbs")
    refute_same files, first
    refute_same files.fetch("untouched.rbs"), first.fetch("untouched.rbs")
  end
end
