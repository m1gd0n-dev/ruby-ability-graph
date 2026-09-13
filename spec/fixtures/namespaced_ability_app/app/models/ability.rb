# frozen_string_literal: true

require "cancancan"

class Document; end

# A namespaced Ability class, as many Rails-engine gems provide (e.g.
# Solidus's Spree::Ability) -- regression fixture for --ability-class.
module Spree
  class Ability
    include CanCan::Ability

    def initialize(user)
      can :read, Document
      can :update, Document, user_id: user.id
    end
  end
end
