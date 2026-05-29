require "time"

module Textus
  module Domain
    class Staleness
      # Reports staleness for generator-zone entries — derived files whose
      # generator's listed sources have been modified more recently than the
      # entry's `_meta.generated.at` timestamp. Returns an Array of row hashes
      # (possibly empty) per entry.
      class GeneratorCheck
        def initialize(manifest:, file_stat:, clock:)
          @manifest  = manifest
          @file_stat = file_stat
          @clock     = clock
        end

        def rows_for(mentry)
          return [] unless mentry.in_generator_zone?(@manifest.policy)
          return [] unless mentry.is_a?(Textus::Manifest::Entry::Derived)

          src = mentry.source
          return [] unless src.is_a?(Textus::Manifest::Entry::Derived::External)

          path = Textus::Key::Path.resolve(@manifest.data, mentry)
          return [stale_row(mentry, path, "derived entry has never been generated")] unless @file_stat.exists?(path)

          parsed = Entry.for_format(mentry.format).parse(@file_stat.read(path), path: path)
          generated_at = parsed["_meta"].dig("generated", "at")
          return [stale_row(mentry, path, "missing generated.at frontmatter")] unless generated_at

          gen_time = parse_time(generated_at)
          return [stale_row(mentry, path, "unparseable generated.at: #{generated_at.inspect}")] unless gen_time

          offender = newest_source_after(src, gen_time)
          return [stale_row(mentry, path, "source '#{offender}' modified after generated.at")] if offender

          []
        end

        private

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
          abs = File.absolute_path?(src) ? src : File.join(File.dirname(@manifest.data.root), src)
          if @file_stat.directory?(abs)
            @file_stat.glob(File.join(abs, "**", "*")).each do |fp|
              next unless !@file_stat.directory?(fp) && @file_stat.exists?(fp)
              return src if @file_stat.mtime(fp) > gen_time
            end
            nil
          elsif @file_stat.exists?(abs) && @file_stat.mtime(abs) > gen_time
            src
          end
        end

        def stale_row(mentry, path, reason)
          {
            "key" => mentry.key,
            "path" => path,
            "generator" => mentry.raw["compute"],
            "reason" => reason,
          }
        end
      end
    end
  end
end
