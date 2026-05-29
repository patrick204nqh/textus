module Textus
  class Manifest
    class Entry
      class Nested < Base
        PUBLISH_EACH_VARS   = Validators::PublishEach::KNOWN_VARS
        PUBLISH_EACH_VAR_RE = Validators::PublishEach::VAR_RE

        attr_reader :index_filename, :publish_each

        def initialize(index_filename: nil, publish_each: nil, **rest)
          super(**rest)
          @index_filename = index_filename
          @publish_each = publish_each
        end

        def nested? = true

        def publish_target_for(full_key)
          return nil if @publish_each.nil?

          entry_segs = @key.split(".")
          key_segs = full_key.split(".")
          raise UsageError.new("key '#{full_key}' is not under entry '#{@key}'") unless key_segs[0, entry_segs.length] == entry_segs

          remaining = key_segs[entry_segs.length..] || []
          leaf = remaining.join("/")
          basename = remaining.last || ""
          ext = Textus::Entry.for_format(@format).extensions.first.to_s.sub(/^\./, "")

          vars = { "leaf" => leaf, "basename" => basename, "key" => full_key, "ext" => ext }
          @publish_each.gsub(PUBLISH_EACH_VAR_RE) { vars.fetch(::Regexp.last_match(1)) }
        end

        def publish_via(pctx, prefix: nil)
          return nil if @publish_each.nil?

          leaves = []
          pctx.manifest.resolver.enumerate(prefix: @key).each do |row|
            next unless row[:manifest_entry].equal?(self)
            next if prefix && !row[:key].start_with?(prefix) && row[:key] != prefix

            target_rel = publish_target_for(row[:key])
            target_abs = File.expand_path(File.join(pctx.repo_root, target_rel))
            unless target_abs.start_with?(File.expand_path(pctx.repo_root) + File::SEPARATOR)
              raise Textus::PublishError.new(
                "entry '#{@key}': publish_each target '#{target_rel}' for key '#{row[:key]}' escapes repo root",
              )
            end

            Textus::Ports::Publisher.publish(source: row[:path], target: target_abs, store_root: pctx.root)
            pctx.emit(:file_published,
                      key: row[:key],
                      envelope: pctx.reader.call(row[:key]),
                      source: row[:path],
                      target: target_abs)
            leaves << { "key" => row[:key], "source" => row[:path], "target" => target_abs }
          end

          { kind: :leaves, value: leaves }
        end

        KIND = :nested

        def self.from_raw(common, raw)
          new(
            index_filename: raw["index_filename"],
            publish_each: raw["publish_each"],
            **common,
          )
        end

        Entry::REGISTRY[KIND] = self
      end
    end
  end
end
