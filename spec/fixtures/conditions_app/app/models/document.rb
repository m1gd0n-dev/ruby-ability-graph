# frozen_string_literal: true

class Document
  # Stubs a real ActiveRecord association reflection, so Harness/Enumerator
  # can be exercised against a `requires_association_traversal` case without
  # needing an actual ActiveRecord dependency in this fixture.
  def self.reflect_on_association(name)
    name == :project ? :fake_reflection : nil
  end
end
