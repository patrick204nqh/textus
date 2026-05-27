require "time"

module Textus
  module Domain
    class Staleness
      # Reports staleness for generator-zone entries — derived files whose
      # generator's listed sources have been modified more recently than the
      # entry's `_meta.generated.at` timestamp. Returns an Array of row hashes
      # (possibly empty) per entry.
      class GeneratorCheck
        def initialize(manifest:)
          @manifest = manifest
        end

        def rows_for(mentry)
          return [] unless mentry.in_generator_zone?

          gen = mentry.generator
          return [] unless gen

          path = Textus::Key::Path.resolve(@manifest, mentry)
          return [stale_row(mentry, path, "derived entry has never been generated")] unless File.exist?(path)

          parsed = Entry.for_format(mentry.format).parse(File.binread(path), path: path)
          generated_at = parsed["_meta"].dig("generated", "at")
          return [stale_row(mentry, path, "missing generated.at frontmatter")] unless generated_at

          gen_time = parse_time(generated_at)
          return [stale_row(mentry, path, "unparseable generated.at: #{generated_at.inspect}")] unless gen_time

          offender = newest_source_after(gen, gen_time)
          return [stale_row(mentry, path, "source '#{offender}' modified after generated.at")] if offender

          []
        end

        private

        def parse_time(str)
          Time.parse(str.to_s)
        rescue StandardError
          nil
        end

        def newest_source_after(gen, gen_time)
          Array(gen["sources"]).each do |src|
            offender = check_source(src, gen_time)
            return offender if offender
          end
          nil
        end

        def check_source(src, gen_time)
          if src.match?(/\A[a-z0-9.][a-z0-9._-]*\z/) && !src.include?("/")
            @manifest.resolver.enumerate(prefix: src).each do |row|
              return src if File.mtime(row[:path]) > gen_time
            end
            nil
          else
            check_filesystem_source(src, gen_time)
          end
        end

        def check_filesystem_source(src, gen_time)
          abs = File.absolute_path?(src) ? src : File.join(File.dirname(@manifest.root), src)
          if File.directory?(abs)
            Dir.glob(File.join(abs, "**", "*")).each do |fp|
              next unless File.file?(fp)
              return src if File.mtime(fp) > gen_time
            end
            nil
          elsif File.exist?(abs) && File.mtime(abs) > gen_time
            src
          end
        end

        def stale_row(mentry, path, reason)
          {
            "key" => mentry.key,
            "path" => path,
            "generator" => mentry.generator,
            "reason" => reason,
          }
        end
      end
    end
  end
end
