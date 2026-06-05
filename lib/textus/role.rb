module Textus
  module Role
    # The three role archetypes, each string sourced exactly once: human curates
    # canon, agent proposes, automation ingests and reconciles (explanation/concepts.md).
    # Reference these constants instead of bare literals (ADR 0044).
    HUMAN      = "human".freeze
    AGENT      = "agent".freeze
    AUTOMATION = "automation".freeze

    # The closed set of legal role names (ADR 0045), built FROM the archetypes
    # above so it stays the single source of truth — a manifest declaring any
    # other name is rejected at load, and DEFAULT ∈ NAMES holds structurally.
    # Capabilities (`can:`) remain freely tunable per role.
    NAMES = [HUMAN, AGENT, AUTOMATION].freeze

    # Default acting identity (ADR 0040): a *choice* over the vocabulary, not a
    # new name. CLI callers act as the human; an agent over stdio proposes and
    # does not inherit the human's authority (it defaults to AGENT per transport).
    DEFAULT = HUMAN

    def self.resolve(root:, flag: nil, env: ENV, default: DEFAULT)
      candidate = flag || env["TEXTUS_ROLE"] || read_file(root) || default
      raise InvalidRole.new(candidate) unless NAMES.include?(candidate)

      candidate
    end

    def self.read_file(root)
      path = File.join(root, "role")
      return nil unless File.exist?(path)

      File.read(path).strip.then { |s| s.empty? ? nil : s }
    end
  end
end
