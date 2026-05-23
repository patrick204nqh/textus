require "json"
require "time"

module Textus
  class Store
    class AuditLog
      def initialize(root)
        @path = File.join(root, "audit.log")
      end

      def last_writer_for(key)
        return nil unless File.exist?(@path)

        last_role = nil
        File.foreach(@path) do |line|
          parsed = parse_row(line.chomp)
          next unless parsed
          next unless parsed["key"] == key
          next unless %w[put delete].include?(parsed["verb"])

          last_role = parsed["role"]
        end
        last_role
      end

      def append(role:, verb:, key:, etag_before:, etag_after:, extras: nil)
        row = {
          "ts" => Time.now.utc.iso8601,
          "role" => role,
          "verb" => verb,
          "key" => key,
          "etag_before" => etag_before,
          "etag_after" => etag_after,
        }

        if extras.is_a?(Hash) && !extras.empty?
          extras = extras.dup
          %w[from_key to_key uid].each do |k|
            row[k] = extras.delete(k) if extras.key?(k)
          end
          row["extras"] = extras unless extras.empty?
        end

        File.open(@path, File::WRONLY | File::APPEND | File::CREAT, 0o644) do |f|
          f.flock(File::LOCK_EX)
          f.write(JSON.generate(row) + "\n")
        end
      end

      # Returns an array of integrity-violation descriptors for the on-disk log.
      # Each entry is { "lineno" => Integer, "reason" => String, "detail" => String }.
      # Empty array means the log is well-formed (or doesn't exist yet).
      def verify_integrity
        return [] unless File.exist?(@path)

        out = []
        File.foreach(@path).with_index(1) do |line, lineno|
          violation = check_line(line.chomp, lineno)
          out << violation if violation
        end
        out
      end

      private

      def parse_row(line)
        return nil if line.empty?

        if line.start_with?("{")
          JSON.parse(line)
        else
          # Legacy TSV (pre-0.5): read-only support retained for on-disk logs
          # written by older textus versions. Never written by current code.
          # Format: ts, role, verb, key, etag_before, etag_after [, json_extras]
          fields = line.split("\t")
          return nil if fields.length < 4

          { "ts" => fields[0], "role" => fields[1], "verb" => fields[2], "key" => fields[3] }
        end
      rescue JSON::ParserError
        nil
      end

      def check_line(stripped, lineno)
        return nil if stripped.empty?

        if stripped.start_with?("{")
          begin
            JSON.parse(stripped)
            nil
          rescue JSON::ParserError => e
            { "lineno" => lineno, "reason" => "invalid_json", "detail" => e.message }
          end
        else
          # parse_row accepts >= 4 fields for read-compat; integrity requires
          # all 6 data columns of the legacy TSV format.
          fields = stripped.split("\t")
          return nil if fields.length >= 6

          {
            "lineno" => lineno,
            "reason" => "short_tsv",
            "detail" => "legacy TSV row has #{fields.length} fields (expected >= 6)",
          }
        end
      end
    end
  end
end
