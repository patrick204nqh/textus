require "json"
require "time"

module Textus
  module Read
    # Queries .textus/.run/audit/audit.log. Filters: key, zone, role, verb, since,
    # correlation_id, limit. Reads the log file as JSON-Lines (legacy TSV
    # rows produce nil and are skipped).
    class Audit
      # Value object that carries all filter parameters for an audit query.
      # `matches?` checks the manifest-independent predicates so the loop body
      # only needs to handle the zone check (which requires manifest access).
      Query = Data.define(:key, :zone, :role, :verb, :since, :seq_since, :correlation_id, :limit) do
        # rubocop:disable Metrics/ParameterLists
        def self.build(key: nil, zone: nil, role: nil, verb: nil,
                       since: nil, seq_since: nil, correlation_id: nil, limit: nil)
          new(key:, zone:, role:, verb:, since:, seq_since:, correlation_id:, limit:)
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

      extend Textus::Contract::DSL

      verb     :audit
      summary  "Query the audit log with optional filters."
      surfaces :cli
      cli      "audit"
      # #call(**filters) — args map to Query.build keyword params (ADR 0063)
      arg :key,            String,  required: false, description: "filter to rows for this key"
      arg :zone,           String,  required: false, description: "filter to keys in this zone"
      arg :role,           String,  required: false, description: "filter to rows written under this role"
      arg :verb,           String,  required: false, description: "filter to rows for this verb"
      arg :since,          String,  required: false,
                                    coerce: ->(s) { Textus::Read::Audit.parse_since(s, now: Time.now) },
                                    description: "ISO-8601 timestamp or relative offset (e.g. 1h, 30m)"
      arg :seq_since,      Integer, required: false, description: "return rows with seq > this cursor value"
      arg :correlation_id, String,  required: false, description: "filter to rows with this correlation_id"
      arg :limit,          Integer, required: false, description: "maximum number of rows to return"
      view(:cli) { |rows, _i| { "verb" => "audit", "rows" => rows } }

      def initialize(container:, call: nil) # rubocop:disable Lint/UnusedMethodArgument
        @manifest  = container.manifest
        @root      = container.root
        @log_path  = Textus::Layout.audit_log(container.root)
        @audit_log = container.audit_log
      end

      def call(**filters)
        query = Query.build(**filters)
        check_cursor_expiry!(query.seq_since)

        files = all_log_files
        return [] if files.empty?

        rows = []
        files.each do |file|
          File.foreach(file) do |line|
            parsed = parse_row(line.chomp)
            next unless parsed
            next unless query.matches?(parsed)
            next if query.zone && !key_in_zone?(parsed["key"], query.zone)

            rows << parsed
            break if limit_reached?(rows, query)
          end
          break if limit_reached?(rows, query)
        end
        rows
      end

      # Accepts ISO8601 ("2026-01-15", "2026-01-15T10:00:00Z") or a relative
      # offset matching /\A(\d+)([smhd])\z/. Returns nil for unparseable input.
      def self.parse_since(str, now: Time.now.utc)
        return nil if str.nil? || str.empty?
        return Time.parse(str) if str =~ /\A\d{4}-\d{2}-\d{2}/

        m = str.match(/\A(\d+)([smhd])\z/) or return nil
        mult = { "s" => 1, "m" => 60, "h" => 3600, "d" => 86_400 }[m[2]]
        now - (m[1].to_i * mult)
      end

      private

      def limit_reached?(rows, query) = query.limit && rows.length >= query.limit

      def check_cursor_expiry!(seq_since)
        return unless seq_since

        log = @audit_log || Textus::Ports::AuditLog.new(@root)
        min = log.min_available_seq
        raise Textus::CursorExpired.new(requested: seq_since, min_available: min) if min && seq_since < min - 1
      end

      def all_log_files
        rotated = Dir.glob(File.join(Textus::Layout.audit_dir(@root), "audit.log.*"))
                     .reject { |p| p.end_with?(".meta.json") }
                     .sort_by { |p| -p.scan(/\d+$/).first.to_i } # .5 .4 .3 .2 .1 → oldest first
        active = File.exist?(@log_path) ? [@log_path] : []
        rotated + active
      end

      def parse_row(line)
        return nil if line.empty?
        return nil unless line.start_with?("{")

        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end

      def key_in_zone?(key, zone)
        mentry = @manifest.resolver.resolve(key).entry
        mentry && mentry.zone == zone
      rescue Textus::Error
        false
      end
    end
  end
end
