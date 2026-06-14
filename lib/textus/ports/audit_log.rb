require "fileutils"
require "json"
require "time"

module Textus
  module Ports
    # Append-only audit log adapter: writes and rotates the on-disk audit JSONL
    # under the store root. An instantiable class — it holds collaborators (the
    # root path + size/keep config), so each store binds its own instance. It
    # already satisfied ADR 0109's single-shape rule (every port is an
    # instantiable class) before that ADR's Clock/Publisher conversions, so it
    # was unchanged by them.
    class AuditLog
      DEFAULT_MAX_SIZE = 10_485_760
      DEFAULT_KEEP = 5

      def initialize(root, max_size: DEFAULT_MAX_SIZE, keep: DEFAULT_KEEP)
        @root     = root
        @path     = Textus::Layout.audit_log(root)
        @max_size = max_size
        @keep     = keep
      end

      def last_writer_for(key)
        return nil unless File.exist?(@path)

        last_role = nil
        File.foreach(@path) do |line|
          parsed = parse_row(line.chomp)
          next unless parsed
          next unless parsed["key"] == key
          next unless %w[put delete key_delete].include?(parsed["verb"])

          last_role = parsed["role"]
        end
        last_role
      end

      def latest_seq
        return scan_max_seq(@path) if File.exist?(@path) && File.size(@path).positive?

        # Active log is empty/missing — consult the most recent rotated file's sidecar.
        meta = read_meta(1)
        return meta["max_seq"] if meta

        0
      end

      def min_available_seq
        rotated_metas = (1..@keep).map { |n| read_meta(n) }.compact
        if rotated_metas.any?
          rotated_metas.map { |m| m["min_seq"] }.min
        elsif File.exist?(@path)
          File.foreach(@path) do |line|
            parsed = parse_row(line.chomp)
            return parsed["seq"] if parsed && parsed["seq"]
          end
          nil
        end
      end

      def append(role:, verb:, key:, etag_before:, etag_after:, extras: nil)
        FileUtils.mkdir_p(File.dirname(@path))
        File.open(@path, File::WRONLY | File::APPEND | File::CREAT, 0o644) do |f|
          f.flock(File::LOCK_EX)
          next_seq = current_max_seq_unlocked + 1
          row = assemble_row(next_seq, { role: role, verb: verb, key: key,
                                         etag_before: etag_before, etag_after: etag_after }, extras)
          f.write(JSON.generate(row) + "\n")
          f.flush
          rotate!(f) if f.size > @max_size
        end
      end

      # Returns an array of integrity-violation descriptors for the on-disk log.
      # Each entry is { "lineno" => Integer, "reason" => String, "detail" => String }.
      # Empty array means the log is well-formed (or doesn't exist yet).
      def verify_integrity
        return [] unless File.exist?(@path)

        [].tap do |out|
          iterate_with_prev_seq do |line, lineno, prev_seq|
            check_line_integrity(line, lineno, prev_seq, out)
          end
        end
      end

      private

      def iterate_with_prev_seq
        prev_seq = nil
        File.foreach(@path).with_index(1) do |line, lineno|
          yield line.chomp, lineno, prev_seq
          parsed = parse_row(line.chomp)
          prev_seq = parsed["seq"] if parsed&.dig("seq").is_a?(Integer)
        end
      end

      def check_line_integrity(line, lineno, prev_seq, out)
        violation = check_line(line, lineno)
        if violation
          out << violation
          return
        end

        parsed = parse_row(line)
        return unless parsed && (seq = parsed["seq"]).is_a?(Integer)
        return unless prev_seq && seq != prev_seq + 1

        out << {
          "lineno" => lineno,
          "reason" => "seq_gap",
          "detail" => "expected #{prev_seq + 1}, got #{seq}",
        }
      end

      def rotated(n)
        File.join(Textus::Layout.audit_dir(@root), "audit.log.#{n}")
      end

      def rotated_meta(n)
        File.join(Textus::Layout.audit_dir(@root), "audit.log.#{n}.meta.json")
      end

      # Caller holds the flock. Returns the highest seq across the active log,
      # OR the most-recent rotated file's max_seq if the active log is empty.
      def current_max_seq_unlocked
        return scan_max_seq(@path) if File.exist?(@path) && File.size(@path).positive?

        meta = read_meta(1)
        meta ? meta["max_seq"] : 0
      end

      def scan_max_seq(file)
        last = 0
        File.foreach(file) do |line|
          parsed = parse_row(line.chomp)
          last = parsed["seq"] if parsed && parsed["seq"].is_a?(Integer)
        end
        last
      end

      def scan_seq_range(file)
        min = nil
        max = 0
        File.foreach(file) do |line|
          parsed = parse_row(line.chomp)
          next unless parsed && parsed["seq"]

          min ||= parsed["seq"]
          max = parsed["seq"]
        end
        [min, max]
      end

      def read_meta(n)
        path = rotated_meta(n)
        return nil unless File.exist?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError
        nil
      end

      def assemble_row(seq, fields, extras = nil)
        row = {
          "seq" => seq,
          "ts" => Time.now.utc.iso8601,
          "role" => fields[:role],
          "verb" => fields[:verb],
          "key" => fields[:key],
          "etag_before" => fields[:etag_before],
          "etag_after" => fields[:etag_after],
        }

        if extras.is_a?(Hash) && !extras.empty?
          extras = extras.dup
          %w[from_key to_key uid].each do |k|
            row[k] = extras.delete(k) if extras.key?(k)
          end
          row["extras"] = extras unless extras.empty?
        end

        row
      end

      # Called inside the flock, after a successful write that pushed size over max.
      # Renames audit.log → audit.log.1 (shifting older files), writes sidecar meta.
      def rotate!(open_file)
        open_file.flush
        min_seq, max_seq = scan_seq_range(@path)
        meta = { "min_seq" => min_seq, "max_seq" => max_seq, "rotated_at" => Time.now.utc.iso8601 }

        # Drop the file that would be shifted past @keep.
        FileUtils.rm_f(rotated(@keep))
        FileUtils.rm_f(rotated_meta(@keep))

        # Shift .N → .(N+1) for N = keep-1 down to 1.
        (@keep - 1).downto(1) do |n|
          File.rename(rotated(n), rotated(n + 1)) if File.exist?(rotated(n))
          File.rename(rotated_meta(n), rotated_meta(n + 1)) if File.exist?(rotated_meta(n))
        end

        # Active log → .1
        File.rename(@path, rotated(1))
        File.write(rotated_meta(1), JSON.generate(meta) + "\n")
        # Next append will create a fresh audit.log via File::CREAT.
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
