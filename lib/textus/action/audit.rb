# frozen_string_literal: true

require "json"
require "time"

module Textus
  module Action
    class Audit < Base
      extend Textus::Contract::DSL

      verb :audit
      summary "Query the audit log with optional filters."
      surfaces :cli
      cli "audit"
      arg :key, String, required: false, description: "filter to rows for this key"
      arg :lane, String, required: false, description: "filter to keys in this lane"
      arg :role, String, required: false, description: "filter to rows written under this role"
      arg :verb, String, required: false, description: "filter to rows for this verb"
      arg :since, String, required: false,
                          coerce: ->(s) { Textus::Action::Audit.parse_since(s, now: Time.now) },
                          description: "ISO-8601 timestamp or relative offset (e.g. 1h, 30m)"
      arg :seq_since, Integer, required: false, description: "return rows with seq > this cursor value"
      arg :correlation_id, String, required: false, description: "filter to rows with this correlation_id"
      arg :limit, Integer, required: false, description: "maximum number of rows to return"
      view(:cli) { |rows, _i| { "verb" => "audit", "rows" => rows } }

      def initialize(**kwargs)
        super()
        @query = Query.build(**kwargs.slice(:key, :lane, :role, :verb, :since, :seq_since, :correlation_id, :limit))
      end

      def args
        @query.to_h.compact
      end

      def call(container:, **)
        @manifest = container.manifest
        @audit_log = container.audit_log

        query = @query
        check_cursor_expiry!(query.seq_since)

        @audit_log.scan(
          seq_since: query.seq_since,
          key: query.key,
          role: query.role,
          verb: query.verb,
          correlation_id: query.correlation_id,
          limit: query.limit,
        ).select do |row|
          next false if query.lane && !key_in_lane?(row["key"], query.lane)
          next false if query.since && (row["ts"].nil? || Time.parse(row["ts"]) < query.since)

          true
        end
      end

      def self.parse_since(str, now: Time.now.utc)
        return nil if str.nil? || str.empty?
        return Time.parse(str) if str =~ /\A\d{4}-\d{2}-\d{2}/

        match = str.match(/\A(\d+)([smhd])\z/) or return nil
        mult = { "s" => 1, "m" => 60, "h" => 3600, "d" => 86_400 }[match[2]]
        now - (match[1].to_i * mult)
      end

      Query = Data.define(:key, :lane, :role, :verb, :since, :seq_since, :correlation_id, :limit) do
        # rubocop:disable Metrics/ParameterLists
        def self.build(key: nil, lane: nil, role: nil, verb: nil,
                       since: nil, seq_since: nil, correlation_id: nil, limit: nil)
          new(key:, lane:, role:, verb:, since:, seq_since:, correlation_id:, limit:)
        end
        # rubocop:enable Metrics/ParameterLists

        def matches?(row)
          return false if key && row["key"] != key
          return false if role && row["role"] != role
          return false if verb && row["verb"] != verb
          return false if since && (row["ts"].nil? || Time.parse(row["ts"]) < since)
          return false if seq_since && (row["seq"].nil? || row["seq"] <= seq_since)
          return false if correlation_id && row.dig("extras", "correlation_id") != correlation_id

          true
        end
      end

      private

      def check_cursor_expiry!(seq_since)
        return unless seq_since

        log = @audit_log || Textus::Port::AuditLog.new(@root)
        min = log.min_available_seq
        raise Textus::CursorExpired.new(requested: seq_since, min_available: min) if min && seq_since < min - 1
      end

      def key_in_lane?(key, lane)
        mentry = @manifest.resolver.resolve(key).entry
        mentry && mentry.lane == lane
      rescue Textus::Error
        false
      end
    end
  end
end
