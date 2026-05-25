require "json"
require "time"

module Textus
  class Store
    class AuditLog
      LEGACY_ROLES = %w[ai script build].freeze

      def initialize(root)
        @path = File.join(root, "audit.log")
      end

      def last_writer_for(key)
        return nil unless File.exist?(@path)

        last_role = nil
        File.foreach(@path).with_index(1) do |line, lineno|
          parsed = parse_row(line.chomp, lineno: lineno)
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

      def parse_row(line, lineno: nil)
        return nil if line.empty?

        row = JSON.parse(line)
        raise LegacyAuditRoles.new(role: row["role"], line: lineno, path: @path) if LEGACY_ROLES.include?(row["role"])

        row
      rescue JSON::ParserError
        nil
      end

      def check_line(stripped, lineno)
        return nil if stripped.empty?

        JSON.parse(stripped)
        nil
      rescue JSON::ParserError => e
        { "lineno" => lineno, "reason" => "invalid_json", "detail" => e.message }
      end
    end
  end
end
