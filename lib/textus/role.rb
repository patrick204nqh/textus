module Textus
  module Role
    # The three role archetypes, each string sourced exactly once: human curates
    # canon, agent proposes, automation fetches/builds (explanation/concepts.md).
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

    # Syntactic shape of an `owner:` subject token (e.g. the `patrick` in
    # `human:patrick`); consumed by `.valid_owner?` (ADR 0045 D1). Acting-role
    # names are gated against the closed NAMES set in .resolve, not by this regex.
    PATTERN = /\A[a-z][a-z0-9_-]*\z/

    # An `owner:` token is either a bare archetype (`agent`) or
    # `<archetype>:<subject>` (`human:patrick`). The archetype is gated against
    # the closed NAMES set (so attribution can't smuggle in a name the role side
    # rejects, ADR 0045 D1); the subject is the free-form principal, validated by
    # PATTERN. Split on the FIRST ':' only — a subject may not itself contain ':'
    # (PATTERN excludes it), so `human:a:b` is rejected.
    def self.valid_owner?(token)
      return false unless token.is_a?(String) && !token.empty?

      archetype, subject = token.split(":", 2)
      return false unless NAMES.include?(archetype)
      return true if subject.nil?

      PATTERN.match?(subject)
    end

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
