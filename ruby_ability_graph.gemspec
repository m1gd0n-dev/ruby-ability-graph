# frozen_string_literal: true

require_relative "lib/ruby_ability_graph/version"

Gem::Specification.new do |spec|
  spec.name = "ruby_ability_graph"
  spec.version = RubyAbilityGraph::VERSION
  spec.authors = ["Jessica Grider"]

  spec.summary = "Maps CanCanCan authorization rules into a visual, queryable 'who can access what' model."
  spec.description = <<~DESC
    ruby_ability_graph loads a Rails app's CanCanCan Ability class in isolation,
    enumerates roles x actions x models, and reports resolved permissions --
    distinguishing patterns it can fully resolve from ones it honestly flags as
    unsupported rather than guessing.
  DESC
  spec.homepage = "https://github.com/m1gd0n-dev/ruby-ability-graph"
  spec.license = "AGPL-3.0-or-later"
  spec.required_ruby_version = ">= 4.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.glob("{lib,exe}/**/*") + %w[README.md LICENSE.txt]
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.add_dependency "prism", "~> 1.0"
end
