require_relative "schema"
require_relative "capabilities"

module Textus
  class Manifest
    # Immutable, parsed view of a manifest YAML document.
    #
    # Holds raw structural data (zones, entries, audit_config, role_caps)
    # but no behaviour beyond accessors. Behaviour (zone authority, key
    # resolution, rules) lives on Manifest::Policy / Resolver / Rules.
    class Data
      AUDIT_DEFAULTS = { max_size: 10_485_760, keep: 5 }.freeze
      WORKER_DEFAULTS = { pool: 4, poll: 5, lease_ttl: 60, max_attempts: 3 }.freeze

      attr_reader :raw, :root, :entries, :declared_zone_kinds,
                  :zone_descs, :zone_owners,
                  :audit_config, :worker_config, :role_caps, :policy

      def self.validate_key!(key)
        raise UsageError.new("empty key") if key.nil? || key.empty?

        Key::Grammar.validate!(key)
      end

      # Forwarder used by Resolver and Entry classes that received a Data
      # but were written against the historical Manifest API.
      def validate_key!(key) = self.class.validate_key!(key)

      def self.parse(raw, root:)
        raise BadFrontmatter.new(File.join(root.to_s, "manifest.yaml"), "manifest must declare zones:") if Array(raw["zones"]).empty?

        Schema.validate!(raw)
        new(raw: raw, root: root)
      end

      def initialize(raw:, root:)
        @raw = raw
        @root = root
        # Write authority is derived from capabilities × zone-kind (ADR 0030),
        # not a per-zone writer list. "Which zones are declared" lives in the
        # one kind-keyed map below (declared_zone_kinds); membership checks by
        # read-side callers (boot, maintenance/data_mv) use its keyset (ADR 0034).
        @declared_zone_kinds = Array(raw["zones"]).to_h do |z|
          [z["name"], z["kind"]&.to_sym]
        end
        @zone_descs  = Array(raw["zones"]).to_h { |z| [z["name"], z["desc"]] }
        # Only zones that actually declare an owner — keep nil-tombstones out so a
        # future `zone_owners.key?(name)` means "owner declared", not "zone exists".
        @zone_owners = Array(raw["zones"]).to_h { |z| [z["name"], z["owner"]] }.compact
        @audit_config = build_audit_config(raw)
        @worker_config = build_worker_config(raw)
        @role_caps = Capabilities.resolve(raw["roles"])
        # Policy is constructed before entries because Entry validators
        # use the entry's own `derived?` and similar helpers that call into
        # Policy; Policy must exist before entries are built.
        @policy = Policy.new(self)
        @entries = build_entries(raw)
        validate_declared_keys!
        freeze
      end

      private

      def build_audit_config(raw)
        a = raw["audit"] || {}
        {
          max_size: a["max_size"] || AUDIT_DEFAULTS[:max_size],
          keep: a["keep"] || AUDIT_DEFAULTS[:keep],
        }.freeze
      end

      # Worker/queue tunables (ADR: job-queue execution model). All optional;
      # the daemon (serve) and batch drain read these, falling back to defaults
      # so a manifest with no `worker:` block runs the queue out of the box.
      def build_worker_config(raw)
        w = raw["worker"] || {}
        {
          pool: w["pool"] || WORKER_DEFAULTS[:pool],
          poll: w["poll"] || WORKER_DEFAULTS[:poll],
          lease_ttl: w["lease_ttl"] || WORKER_DEFAULTS[:lease_ttl],
          max_attempts: w["max_attempts"] || WORKER_DEFAULTS[:max_attempts],
        }.freeze
      end

      def build_entries(raw)
        Array(raw["entries"]).map do |e|
          entry = Manifest::Entry::Parser.call(e)
          Manifest::Entry::Validators.run_all(entry, policy: @policy)
          entry
        end.freeze
      end

      def validate_declared_keys!
        @entries.each do |e|
          raise UsageError.new("empty key") if e.key.nil? || e.key.empty?

          Key::Grammar.validate!(e.key)
        end
      end
    end
  end
end
