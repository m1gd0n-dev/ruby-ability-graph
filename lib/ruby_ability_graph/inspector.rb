# frozen_string_literal: true

require "prism"

module RubyAbilityGraph
  # Static source scan (via Prism, never executes the target) that lists
  # every method called on `user` in Ability#initialize -- a roles-file
  # authoring aid.
  class Inspector
    class InspectionError < StandardError; end

    Result = Struct.new(:method_names, :warning, keyword_init: true)

    def initialize(ability_file:, ability_class_name: "Ability")
      @ability_file = ability_file
      @ability_class_name = ability_class_name
    end

    def call
      program_node = parse_ability_file
      class_node = require_class_node(program_node)
      init_node = require_init_node(class_node)
      user_param = require_user_param(init_node)

      visitor = UserCallVisitor.new(user_param)
      visitor.visit(init_node.body)

      Result.new(
        method_names: visitor.methods.sort.uniq,
        warning: visitor.block_or_proc? ? block_or_proc_warning : nil
      )
    end

    private

    def parse_ability_file
      raise InspectionError, "No such file: #{@ability_file}" unless File.exist?(@ability_file)

      parse_result = Prism.parse(File.read(@ability_file))
      return parse_result.value unless parse_result.failure?

      messages = parse_result.errors.map(&:message).join("; ")
      raise InspectionError, "Failed to parse #{@ability_file}: #{messages}"
    end

    def require_class_node(program_node)
      find_class_node(program_node) ||
        raise(InspectionError, "Could not find `class #{@ability_class_name}` in #{@ability_file}")
    end

    def require_init_node(class_node)
      find_method_node(class_node, "initialize") ||
        raise(InspectionError, "#{@ability_class_name}#initialize not found in #{@ability_file}")
    end

    def require_user_param(init_node)
      required = init_node.parameters&.requireds&.first
      required&.name&.to_s ||
        raise(InspectionError, "#{@ability_class_name}#initialize takes no parameters to inspect")
    end

    def block_or_proc_warning
      "#{@ability_class_name}#initialize contains a block or proc (e.g. `each { ... }`, `-> { ... }`) -- " \
        "calls on `user` inside it were still counted, but static analysis can't guarantee this list is " \
        "complete for arbitrary control flow. Review #initialize by hand too."
    end

    def find_class_node(node)
      return nil unless node

      finder = ClassNodeFinder.new(@ability_class_name)
      finder.visit(node)
      finder.found
    end

    def find_method_node(class_node, method_name)
      finder = DefNodeFinder.new(method_name)
      finder.visit(class_node)
      finder.found
    end

    # Finds the named class's node in a parsed source tree.
    class ClassNodeFinder < Prism::Visitor
      attr_reader :found

      def initialize(class_name)
        super()
        @class_name = class_name
      end

      def visit_class_node(node)
        @found ||= node if node.constant_path.slice == @class_name
        super unless @found
      end
    end

    # Finds the named method's def node within a class node.
    class DefNodeFinder < Prism::Visitor
      attr_reader :found

      def initialize(method_name)
        super()
        @method_name = method_name
      end

      def visit_def_node(node)
        @found ||= node if node.name.to_s == @method_name
      end
    end

    # Collects every method called on a given local variable name, and
    # flags whether any of those calls happen inside a block or lambda.
    class UserCallVisitor < Prism::Visitor
      attr_reader :methods

      def initialize(local_variable_name)
        super()
        @local_variable_name = local_variable_name
        @methods = []
        @block_or_proc = false
      end

      def block_or_proc?
        @block_or_proc
      end

      def visit_call_node(node)
        receiver = node.receiver
        if receiver.is_a?(Prism::LocalVariableReadNode) && receiver.name.to_s == @local_variable_name
          @methods << node.name.to_s
        end
        super
      end

      def visit_block_node(node)
        @block_or_proc = true
        super
      end

      def visit_lambda_node(node)
        @block_or_proc = true
        super
      end
    end
  end
end
