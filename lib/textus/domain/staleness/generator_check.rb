require "time"

module Textus
  module Domain
    class Staleness
      # Reports staleness for generator-zone entries — derived files whose
      # generator's listed sources have been modified more recently than the
      # entry's `_meta.generated.at` timestamp. Returns an Array of row hashes
      # (possibly empty) per entry.
      class GeneratorCheck
        def initialize(manifest:, file_stat:)
          @manifest  = manifest
          @file_stat = file_stat
        end

        def rows_for(mentry)
          return [] unless applicable?(mentry)

          path = Textus::Key::Path.resolve(@manifest.data, mentry)
          reason = stale_reason(mentry, path)
          reason ? [stale_row(mentry, path, reason)] : []
        end

        private

        def applicable?(mentry)
          mentry.derived? &&
            mentry.external?
        end

        def stale_reason(mentry, path)
          return "derived entry has never been generated" unless @file_stat.exists?(path)

          generated_at = generated_at_of(mentry, path)
          return "missing generated.at frontmatter" unless generated_at

          gen_time = parse_time(generated_at)
          return "unparseable generated.at: #{generated_at.inspect}" unless gen_time

          offender = newest_source_after(mentry.source, gen_time)
          "source '#{offender}' modified after generated.at" if offender
        end

        def generated_at_of(mentry, path)
          Entry.for_format(mentry.format).parse(@file_stat.read(path), path: path)["_meta"].dig("generated", "at")
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

        # FileStat substitute for File.file?: excludes directories but treats
        # special files (FIFOs/sockets/devices) as regular files — acceptable
        # because a generator source tree won't contain them.
        def file?(fpath) = !@file_stat.directory?(fpath) && @file_stat.exists?(fpath)

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
