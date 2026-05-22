require "time"

module Textus
  class Store
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/BlockLength
    class Staleness
      def initialize(manifest:)
        @manifest = manifest
      end

      def call(prefix: nil, zone: nil)
        out = []
        @manifest.entries.each do |mentry|
          next unless mentry.in_generator_zone?
          next if zone && mentry.zone != zone

          gen = mentry.generator
          next unless gen
          next if prefix && !(mentry.key == prefix || mentry.key.start_with?("#{prefix}."))

          path = Textus::Key::Path.resolve(@manifest, mentry)

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

        @manifest.entries.each do |mentry|
          next unless mentry.intake_handler
          next if zone && mentry.zone != zone
          next if prefix && !(mentry.key == prefix || mentry.key.start_with?("#{prefix}."))

          policy_set = @manifest.policies_for(mentry.key)
          ttl = policy_set.refresh&.ttl_seconds
          next unless ttl

          path = Textus::Key::Path.resolve(@manifest, mentry)

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
            @manifest.enumerate(prefix: src).each do |row|
              return src if File.mtime(row[:path]) > gen_time
            end
          else
            abs = File.absolute_path?(src) ? src : File.join(File.dirname(@manifest.root), src)
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

      def intake_stale_row(mentry, path, reason)
        { "key" => mentry.key, "path" => path, "handler" => mentry.intake_handler, "reason" => reason }
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
