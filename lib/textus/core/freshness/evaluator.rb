require "time"

module Textus
  module Core
    module Freshness
      # The single currency evaluator (ADR 0099). Answers "is the stored data
      # stale relative to its retention rule?" and detects generator drift for
      # external entries.
      #   - retention rule TTL -> AGE signal: now - file_basis > ttl_seconds
      #   - external -> DRIFT signal: a source changed since generated.at
      #     (surfaced by the doctor generator_drift check).
      class Evaluator
        def initialize(manifest:, file_stat:, clock:)
          @manifest  = manifest
          @file_stat = file_stat
          @clock     = clock
        end

        # Per-entry currency Verdict driven by the retention rule TTL (if any).
        def verdict(mentry)
          ttl = @manifest.rules.for(mentry.key).retention&.ttl_seconds
          return fresh if ttl.nil?

          stale = age_stale?(file_basis(mentry), ttl)
          Verdict.build(stale: stale, reason: stale ? "ttl exceeded" : nil, fetching: false)
        end

        # Keys of entries past their retention rule TTL — the refresh produce scope.
        def stale_keys(prefix: nil, lane: nil)
          @manifest.data.entries.select { |m| due?(m, prefix: prefix, lane: lane) }.map(&:key)
        end

        alias stale_intake_keys stale_keys

        # File basis as a Time (or nil): file mtime when present, else nil.
        def file_basis(mentry)
          path = @manifest.resolver.resolve(mentry.key).path
          return nil unless @file_stat.exists?(path)

          @file_stat.mtime(path)
        end

        # Generator-drift rows for one entry (replaces Staleness::GeneratorCheck#
        # rows_for) — consumed by the doctor generator_drift check.
        def drift_rows(mentry)
          return [] unless drift_applicable?(mentry)

          path = Textus::Key::Path.resolve(@manifest.data, mentry)
          reason = drift_reason(mentry, path)
          reason ? [drift_row(mentry, path, reason)] : []
        end

        private

        def fresh = Verdict.build(stale: false, reason: nil, fetching: false)

        def due?(mentry, prefix:, lane:)
          return false if lane && mentry.lane != lane
          return false if prefix && !mentry.key.start_with?(prefix)

          ttl = @manifest.rules.for(mentry.key).retention&.ttl_seconds
          return false if ttl.nil?

          path = @manifest.resolver.resolve(mentry.key).path
          return true unless @file_stat.exists?(path)

          age_stale?(file_basis(mentry), ttl)
        end

        # The one age comparison. A never-recorded entry (nil basis) is stale.
        def age_stale?(basis, ttl)
          return true if basis.nil?

          (@clock.now - basis).to_i > ttl
        end

        # --- generator drift (lifted from Staleness::GeneratorCheck) ---

        def drift_applicable?(mentry) = mentry.external?

        def drift_reason(mentry, path)
          return "derived entry has never been generated" unless @file_stat.exists?(path)

          generated_at = generated_at_of(mentry, path)
          return "missing generated.at frontmatter" unless generated_at

          gen_time = parse_time(generated_at)
          return "unparseable generated.at: #{generated_at.inspect}" unless gen_time

          offender = newest_source_after(mentry.source, gen_time)
          "source '#{offender}' modified after generated.at" if offender
        end

        def generated_at_of(mentry, path)
          Format.for(mentry.format).parse(@file_stat.read(path), path: path)["_meta"].dig("generated", "at")
        end

        def parse_time(str)
          Time.parse(str.to_s)
        rescue StandardError
          nil
        end

        def newest_source_after(external_src, gen_time)
          Array(external_src.sources).each do |src|
            offender = check_source(src, gen_time)
            return offender if offender
          end
          nil
        end

        def check_source(src, gen_time)
          if src.match?(/\A[a-z0-9.][a-z0-9._-]*\z/) && !src.include?("/")
            @manifest.resolver.enumerate(prefix: src).each do |row|
              return src if @file_stat.mtime(row[:path]) > gen_time
            end
            nil
          else
            check_filesystem_source(src, gen_time)
          end
        end

        def check_filesystem_source(src, gen_time)
          abs = absolutize_source(src)
          if @file_stat.directory?(abs)
            dir_has_newer_file?(abs, gen_time) ? src : nil
          elsif @file_stat.exists?(abs) && @file_stat.mtime(abs) > gen_time
            src
          end
        end

        def absolutize_source(src)
          File.absolute_path?(src) ? src : File.join(File.dirname(@manifest.data.root), src)
        end

        def dir_has_newer_file?(abs, gen_time)
          @file_stat.glob(File.join(abs, "**", "*")).any? do |fpath|
            file?(fpath) && @file_stat.mtime(fpath) > gen_time
          end
        end

        def file?(fpath) = !@file_stat.directory?(fpath) && @file_stat.exists?(fpath)

        def drift_row(mentry, path, reason)
          { "key" => mentry.key, "path" => path, "generator" => mentry.source.command, "reason" => reason }
        end
      end
    end
  end
end
