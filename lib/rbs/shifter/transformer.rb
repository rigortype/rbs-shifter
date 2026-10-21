# frozen_string_literal: true

require "rbs"
require "stringio"

module RBS
  module Shifter
    class Transformer
      ACTIONS = %w[remove_member replace_member add_member remove_declaration replace_declaration add_declaration].freeze

      class SemanticWriter < RBS::Writer
        def write_comment(_comment); end

        def preserve_empty_line(_previous, _current); end
      end
      private_constant :SemanticWriter

      def initialize(rules:)
        @rules = rules
      end

      def transform(files:, target:)
        output = files.transform_values(&:dup)
        @rules.each do |rule|
          next unless rule.fetch("targets").include?(target)

          apply(output, rule)
        end
        output
      end

      private

      def apply(files, rule)
        action = rule.fetch("action")
        raise Error, "unsupported action #{action.inspect}" unless ACTIONS.include?(action)

        path = rule.fetch("file")
        raise Error, "missing file #{path}" unless files.key?(path)

        name = rule.fetch("declaration")
        raise Error, "declaration must be absolute: #{name}" unless name.start_with?("::")

        _, directives, declarations = RBS::Parser.parse_signature(files.fetch(path))
        if action.end_with?("_member")
          apply_member(declarations, rule)
        else
          apply_declaration(declarations, rule)
        end
        files[path] = write(directives + declarations)
      rescue RBS::ParsingError, KeyError, Error => error
        raise Error, "rule #{rule['id']} (#{rule['file']}): #{error.message}"
      end

      def apply_member(declarations, rule)
        owner, = unique(find_declarations(declarations, rule.fetch("declaration")), "declaration #{rule["declaration"]}")
        raise Error, "declaration #{rule["declaration"]} cannot have members" unless owner.respond_to?(:members)

        members = owner.members
        action = rule.fetch("action")
        before = parse_member(rule.fetch("before"), owner) unless action == "add_member"
        after = parse_member(rule.fetch("after"), owner) unless action == "remove_member"
        index = match_index(members, before) if before
        reject_duplicate_member(members, after, except: index) if after
        case action
        when "remove_member" then members.delete_at(index)
        when "replace_member" then members[index] = after
        when "add_member" then members << after
        end
      end

      def apply_declaration(declarations, rule)
        name = rule.fetch("declaration")
        action = rule.fetch("action")
        after = parse_declaration(rule.fetch("after")) unless action == "remove_declaration"

        if action == "add_declaration"
          raise Error, "duplicate declaration #{name}" unless find_declarations(declarations, name).empty?

          parent, namespace = insertion_parent(declarations, after, name)
          parent << after
        else
          current, parent, namespace = unique(find_declarations(declarations, name), "declaration #{name}")
          before = parse_declaration(rule.fetch("before"))
          unless semantic(current) == semantic(before)
            raise Error, "changed precondition for declaration #{name}"
          end
          index = parent.index(current)
          if action == "remove_declaration"
            parent.delete_at(index)
          else
            unless absolute_name(after, namespace) == name
              raise Error, "replacement declaration must retain name #{name}"
            end
            parent[index] = after
          end
        end
      end

      def parse_member(source, owner)
        kind = case owner
               when RBS::AST::Declarations::Class then "class"
               when RBS::AST::Declarations::Module then "module"
               when RBS::AST::Declarations::Interface then "interface"
               else raise Error, "unsupported member owner #{owner.class}"
               end
        wrapper_name = kind == "interface" ? "_ShiftRule" : "ShiftRule"
        writer = RBS::Writer.new(out: StringIO.new)
        header = writer.name_and_params(wrapper_name, owner.type_params)
        _, directives, declarations = RBS::Parser.parse_signature("#{kind} #{header}\n#{source}\nend\n")
        unless directives.empty? && declarations.length == 1 && declarations.first.members.length == 1
          raise Error, "member snippet must contain exactly one member"
        end
        member = declarations.first.members.first
        raise Error, "declaration supplied as member" if member.is_a?(RBS::AST::Declarations::Base)

        member
      end

      def parse_declaration(source)
        _, directives, declarations = RBS::Parser.parse_signature(source)
        unless directives.empty? && declarations.length == 1
          raise Error, "declaration snippet must contain exactly one declaration"
        end
        declarations.first
      end

      def find_declarations(nodes, name, namespace = "::")
        nodes.flat_map do |node|
          next [] unless node.is_a?(RBS::AST::Declarations::Base)

          full_name = absolute_name(node, namespace)
          matches = full_name == name ? [[node, nodes, namespace]] : []
          matches.concat(find_declarations(node.members, name, "#{full_name}::")) if node.respond_to?(:members)
          matches
        end
      end

      def absolute_name(node, namespace)
        name = node.respond_to?(:new_name) ? node.new_name.to_s : node.name.to_s
        name.start_with?("::") ? name : "#{namespace}#{name}"
      end

      def insertion_parent(declarations, node, name)
        return [declarations, "::"] if absolute_name(node, "::") == name

        relative_name = node.respond_to?(:new_name) ? node.new_name.to_s : node.name.to_s
        suffix = "::#{relative_name}"
        raise Error, "added declaration does not match #{name}" unless name.end_with?(suffix)

        owner_name = name.delete_suffix(suffix)
        owner, = unique(find_declarations(declarations, owner_name), "declaration #{owner_name}")
        raise Error, "declaration #{owner_name} cannot have members" unless owner.respond_to?(:members)

        [owner.members, "#{owner_name}::"]
      end

      def match_index(members, expected)
        matches = members.each_index.select { |index| semantic(members[index]) == semantic(expected) }
        unique(matches, "member precondition")
      end

      def unique(matches, description)
        raise Error, "missing or changed #{description}" if matches.empty?
        raise Error, "ambiguous #{description}" if matches.length > 1

        matches.first
      end

      def reject_duplicate_member(members, candidate, except:)
        identities = member_identities(candidate)
        duplicate = members.each_with_index.any? do |member, index|
          index != except && !(member_identities(member) & identities).empty?
        end
        raise Error, "duplicate member #{identities.inspect}" if duplicate
      end

      def member_identities(member)
        kinds = member.respond_to?(:kind) && member.kind == :singleton_instance ? %i[instance singleton] : [member.respond_to?(:kind) ? member.kind : nil]
        names = case member
                when RBS::AST::Members::MethodDefinition then [member.name]
                when RBS::AST::Members::Alias then [member.new_name]
                when RBS::AST::Members::AttrReader then [member.name]
                when RBS::AST::Members::AttrWriter then [:"#{member.name}="]
                when RBS::AST::Members::AttrAccessor then [member.name, :"#{member.name}="]
                end
        return kinds.product(names).map { |kind, name| [:method, kind, name] } if names

        [[member.class, member.respond_to?(:name) ? member.name.to_s : nil]]
      end

      def semantic(node)
        out = StringIO.new
        writer = SemanticWriter.new(out: out)
        if node.is_a?(RBS::AST::Declarations::Base)
          writer.write_decl(node)
        else
          writer.write_member(node)
        end
        [node.class, out.string]
      end

      def write(nodes)
        out = StringIO.new
        RBS::Writer.new(out: out).write(nodes)
        out.string
      end
    end
  end
end
