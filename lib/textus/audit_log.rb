require "json"
require "time"

module Textus
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
  end
end
