require "json"
require "time"

module Textus
  module Infra
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

      def latest_seq
        return 0 unless File.exist?(@path)

        last = 0
        File.foreach(@path) do |line|
          parsed = parse_row(line.chomp)
          last = parsed["seq"] if parsed && parsed["seq"].is_a?(Integer)
        end
        last
      end

      def append(role:, verb:, key:, etag_before:, etag_after:, extras: nil)
        File.open(@path, File::WRONLY | File::APPEND | File::CREAT, 0o644) do |f|
          f.flock(File::LOCK_EX)
          next_seq = scan_last_seq_unlocked + 1
          row = {
            "seq" => next_seq,
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

      # Caller holds the flock. Returns the highest seq in the active log, or 0.
      def scan_last_seq_unlocked
        return 0 unless File.exist?(@path)

        last = 0
        File.foreach(@path) do |line|
          parsed = parse_row(line.chomp)
          last = parsed["seq"] if parsed && parsed["seq"].is_a?(Integer)
        end
        last
      end

      def parse_row(line)
        return nil if line.empty?

        JSON.parse(line)
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
