require "fileutils"
require "json"
require "time"

module Textus
  module Ports
    class AuditLog
      DEFAULT_MAX_SIZE = 10_485_760
      DEFAULT_KEEP = 5

      def initialize(root, max_size: DEFAULT_MAX_SIZE, keep: DEFAULT_KEEP)
        @root     = root
        @path     = File.join(root, "audit.log")
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
          next unless %w[put delete].include?(parsed["verb"])

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

        out = []
        File.foreach(@path).with_index(1) do |line, lineno|
          violation = check_line(line.chomp, lineno)
          out << violation if violation
        end
        out
      end

      private

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
        path = File.join(@root, "audit.log.#{n}.meta.json")
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
        oldest      = File.join(@root, "audit.log.#{@keep}")
        oldest_meta = File.join(@root, "audit.log.#{@keep}.meta.json")
        FileUtils.rm_f(oldest)
        FileUtils.rm_f(oldest_meta)

        # Shift .N → .(N+1) for N = keep-1 down to 1.
        (@keep - 1).downto(1) do |n|
          src      = File.join(@root, "audit.log.#{n}")
          dst      = File.join(@root, "audit.log.#{n + 1}")
          File.rename(src, dst) if File.exist?(src)

          src_meta = File.join(@root, "audit.log.#{n}.meta.json")
          dst_meta = File.join(@root, "audit.log.#{n + 1}.meta.json")
          File.rename(src_meta, dst_meta) if File.exist?(src_meta)
        end

        # Active log → .1
        File.rename(@path, File.join(@root, "audit.log.1"))
        File.write(File.join(@root, "audit.log.1.meta.json"), JSON.generate(meta) + "\n")
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
