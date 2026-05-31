module Textus
  class Manifest
    # Resolves a manifest's `roles:` block (or the absence of one) into a
    # capability map: { role_name => [verbs] }. Verbs are a subset of the
    # closed capability set (Schema::CAPABILITIES). See ADR 0030.
    module Capabilities
      # Fallback role set for a manifest that omits `roles:` entirely. Agent
      # is intentionally minimal here (`propose` only) — narrower than the
      # `textus init` scaffold, which declares `agent: [propose, keep]` so the
      # default `notebook` workspace is writable. A roles-less manifest that
      # declares a `kind: workspace` zone is therefore rejected at load (no
      # `keep`-holder); declare `roles:` to opt into a workspace lane (ADR 0033).
      DEFAULT_MAPPING = {
        "human" => %w[author propose].freeze,
        "agent" => %w[propose].freeze,
        "automation" => %w[fetch build].freeze,
      }.freeze

      # Returns { role_name => [verbs] }. When `roles:` is declared we use
      # exactly that; defaults are *not* layered in (declaring roles is an
      # opt-in to a fully user-defined vocabulary).
      def self.resolve(raw_roles)
        return DEFAULT_MAPPING if raw_roles.nil?

        raw_roles.to_h { |r| [r["name"], Array(r["can"]).freeze] }.freeze
      end
    end
  end
end
