# frozen_string_literal: true

require_relative "document"

class Ability
  include CanCan::Ability

  def initialize(user)
    if user.admin?
      can :manage, :all
    else
      can :read, Document
      can :update, Document, user_id: user.id
      cannot :destroy, Document
    end
  end
end
