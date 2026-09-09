# frozen_string_literal: true

class Ability
  def initialize(user)
    if user.admin?
      can :manage, :all
    else
      user.team_ids.each { |team_id| can :read, Project, team_id: team_id }
    end
  end
end
