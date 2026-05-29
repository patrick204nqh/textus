require_relative "schema"
require_relative "role_kinds"

module Textus
  class Manifest
    # Immutable, parsed view of a manifest YAML document.
    #
    # Holds raw structural data (zones, entries, audit_config, role_mapping)
    # but no behaviour beyond accessors. Behaviour (zone authority, key
    # resolution, rules) lives on Manifest::Policy / Resolver / Rules.
    class Data
      AUDIT_DEFAULTS = { max_size: 10_485_760, keep: 5 }.freeze

      attr_reader :raw, :root, :entries, :zones, :zone_readers, :audit_config, :role_mapping, :policy

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
        @zones = Array(raw["zones"]).to_h { |z| [z["name"], Array(z["write_policy"])] }
        @zone_readers = Array(raw["zones"]).to_h do |z|
          rp = z["read_policy"]
          [z["name"], rp.nil? ? :all : Array(rp)]
        end
        @audit_config = build_audit_config(raw)
        @role_mapping = RoleKinds.resolve(raw["roles"])
        # Policy is constructed before entries because Entry validators
        # call `entry.in_generator_zone?(policy)` and similar helpers
        # that take Policy as an argument.
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
