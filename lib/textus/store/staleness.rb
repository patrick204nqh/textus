require "time"

module Textus
  class Store
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/BlockLength
    class Staleness
      def initialize(store)
        @store = store
      end

      def call(prefix: nil, zone: nil)
        out = []
        @store.manifest.entries.each do |mentry|
          next unless mentry.zone == "derived"
          next if zone && mentry.zone != zone

          gen = mentry.generator
          next unless gen
          next if prefix && !(mentry.key == prefix || mentry.key.start_with?("#{prefix}."))

          path = Textus::Path.resolve(@store.manifest, mentry)

          unless File.exist?(path)
            out << stale_row(mentry, path, "derived entry has never been generated")
            next
          end

          raw = File.binread(path)
          parsed = Entry.for_format(mentry.format).parse(raw, path: path)
          generated_at = parsed["_meta"].dig("generated", "at")
          unless generated_at
            out << stale_row(mentry, path, "missing generated.at frontmatter")
            next
          end
          gen_time = begin
            Time.parse(generated_at.to_s)
          rescue StandardError
            nil
          end
          unless gen_time
            out << stale_row(mentry, path, "unparseable generated.at: #{generated_at.inspect}")
            next
          end

          offender = newest_source_after(gen, gen_time)
          out << stale_row(mentry, path, "source '#{offender}' modified after generated.at") if offender
        end

        @store.manifest.entries.each do |mentry|
          next unless mentry.fetch
          next if zone && mentry.zone != zone
          next if prefix && !(mentry.key == prefix || mentry.key.start_with?("#{prefix}."))

          ttl = parse_ttl(mentry.ttl)
          next unless ttl

          path = Textus::Path.resolve(@store.manifest, mentry)

          unless File.exist?(path)
            out << intake_stale_row(mentry, path, "never refreshed")
            next
          end

          meta = Entry.for_format(mentry.format).parse(File.binread(path), path: path)["_meta"]
          last_str = meta["last_refreshed_at"]
          if last_str.nil?
            out << intake_stale_row(mentry, path, "never refreshed (no last_refreshed_at)")
            next
          end

          last = begin
            Time.parse(last_str.to_s)
          rescue StandardError
            nil
          end
          out << intake_stale_row(mentry, path, "ttl exceeded (#{ttl}s)") if last.nil? || (Time.now - last) > ttl
        end

        out
      end

      private

      def newest_source_after(gen, gen_time)
        Array(gen["sources"]).each do |src|
          if src.match?(/\A[a-z0-9.][a-z0-9._-]*\z/) && !src.include?("/")
            @store.manifest.enumerate(prefix: src).each do |row|
              return src if File.mtime(row[:path]) > gen_time
            end
          else
            abs = File.absolute_path?(src) ? src : File.join(File.dirname(@store.root), src)
            if File.directory?(abs)
              Dir.glob(File.join(abs, "**", "*")).each do |fp|
                next unless File.file?(fp)
                return src if File.mtime(fp) > gen_time
              end
            elsif File.exist?(abs)
              return src if File.mtime(abs) > gen_time
            end
          end
        end
        nil
      end

      def parse_ttl(s)
        return nil unless s

        m = s.to_s.match(/\A(\d+)([smhd])\z/) or return nil
        n = m[1].to_i
        case m[2]
        when "s" then n
        when "m" then n * 60
        when "h" then n * 3600
        when "d" then n * 86_400
        end
      end

      def intake_stale_row(mentry, path, reason)
        { "key" => mentry.key, "path" => path, "fetch" => mentry.fetch, "reason" => reason }
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
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/BlockLength
  end
end
