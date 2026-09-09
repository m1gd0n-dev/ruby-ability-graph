# frozen_string_literal: true

module RubyAbilityGraph
  # A duck-typed user stand-in, built from a role's attributes hash, that
  # answers whatever methods an Ability class calls on `user`.
  class RoleStandIn
    def initialize(attributes = {})
      @attributes = attributes.transform_keys(&:to_sym)
    end

    def method_missing(name, *args)
      @attributes.key?(name) ? @attributes[name] : super
    end

    def respond_to_missing?(name, include_private = false)
      @attributes.key?(name) || super
    end
  end
end
