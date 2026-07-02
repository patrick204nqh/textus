require_relative "schema"

module Textus
  class Manifest
    class Data
      AUDIT_DEFAULTS = { max_size: 10_485_760, keep: 1000 }.freeze
      WORKER_DEFAULTS = { pool: 4, poll: 5, lease_ttl: 60, max_attempts: 3 }.freeze

      attr_reader :raw, :root, :entries, :declared_lane_kinds,
                  :lane_descs,
                  :audit_config, :worker_config, :role_caps

      def self.validate_key!(key)
        raise UsageError.new("empty key") if key.nil? || key.empty?

        Key::Grammar.validate!(key)
      end

      def validate_key!(key) = self.class.validate_key!(key)

      def self.parse(raw, root:)
        %w[roles lanes owner].each do |stale_key|
          next unless raw.key?(stale_key)

          raise BadManifest.new(
            "unknown top-level key '#{stale_key}' — protocol textus/4 fixes roles/lanes in " \
            "code; remove this section from manifest.yaml (see CHANGELOG)",
          )
        end
        raise BadManifest.new("manifest must declare data:") if Array(raw["data"]).empty? && raw["data"] != {}

        Schema.validate!(raw)
        new(raw: raw, root: root)
      end

      def initialize(raw:, root:)
        @raw = raw
        @root = root
        @declared_lane_kinds = Textus::Protocol::V4::LANES.keys.to_h { |name| [name, name] }
        @lane_descs = Textus::Protocol::V4::LANES.transform_values { |row| row[:desc] }
        @audit_config = build_audit_config(raw)
        @worker_config = build_worker_config(raw)
        @role_caps = {}
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
        (raw["data"] || {}).flat_map do |lane_name, lane_entries|
          unless Textus::Protocol::V4::LANES.key?(lane_name)
            raise BadManifest.new("unknown lane '#{lane_name}' (known: #{Textus::Protocol::V4::LANES.keys.join(", ")})")
          end

          Array(lane_entries).map { |e| Manifest::Entry::Parser.call(e.merge("lane" => lane_name), root: @root) }
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
