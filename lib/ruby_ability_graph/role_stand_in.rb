# frozen_string_literal: true

module RubyAbilityGraph
  # A duck-typed user stand-in, built from a role's attributes hash, that
  # answers whatever methods an Ability class calls on `user`.
  class RoleStandIn
    def initialize(attributes = {})
      @attributes = attributes.transform_keys(&:to_sym).transform_values { |v| wrap(v) }
    end

    def method_missing(name, *args)
      @attributes.key?(name) ? @attributes[name] : super
    end

    def respond_to_missing?(name, include_private = false)
      @attributes.key?(name) || super
    end

    private

    # Recurses into nested Hashes (and Arrays of them) so an Ability class
    # that calls a method on an *associated* stand-in -- e.g.
    # `user.valuator.can_edit_dossier?`, a common real-world CanCanCan
    # pattern -- gets another duck-typed stand-in back, not a plain Hash
    # that doesn't respond to it.
    def wrap(value)
      case value
      when Hash then self.class.new(value)
      when Array then value.map { |v| wrap(v) }
      else value
      end
    end
  end
end
