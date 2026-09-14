# frozen_string_literal: true

module RubyAbilityGraph
  # Strips control chars (e.g. ANSI escapes) before untrusted values hit the terminal.
  module TerminalSafe
    CONTROL_CHARS = /[\p{Cc}&&[^\n]]/

    def self.sanitize(value)
      value.to_s.gsub(CONTROL_CHARS, "")
    end
  end
end
