# frozen_string_literal: true

require "cancancan"
require_relative "document"
require_relative "report"

# One action per classification scenario, so each (action, model) cell in
# the test results has exactly one contributing rule to reason about --
# except :update, which deliberately combines two resolved rules.
class Ability
  include CanCan::Ability

  def initialize(user)
    if user.admin?
      can :manage, :all
    else
      can :read, Document, team_id: user.team_id
      can :update, Document
      cannot :update, Document, archived: true
      can(:destroy, Document) { |doc| doc.owner_id == user.id }
      cannot :export, Document, project: { team_id: user.team_id }
      can :archive, Document, project: user.team_id
      user.extra_team_ids.each { |team_id| can :read, Report, team_id: team_id }
    end
  end
end
