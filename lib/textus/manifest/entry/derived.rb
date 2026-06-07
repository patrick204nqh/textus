module Textus
  class Manifest
    class Entry
      class Derived < Base
        attr_reader :source, :events

        def initialize(source:, events: {}, **rest)
          super(**rest)
          @source = source
          @events = events || {}
        end

        def derived?    = true
        def projection? = @source.projection?
        def external?   = @source.external?

        # ADR 0094: build the DATA artifact (project), then publish via
        # the ONE shared mode (Publish::ToPaths). External (command) entries are
        # produced out-of-band — skip the build, but still publish their existing
        # store bytes through the same mode. A project entry with no targets is a
        # terminal data node: it produced data, so report :built even though
        # nothing was emitted.
        def publish_via(pctx, prefix: nil)
          built = false
          unless external?
            Textus::Write::DataBuilder.new(container: pctx.container, call: pctx.call).run(self)
            built = true
            pctx.emit(:entry_produced, key: @key, envelope: pctx.reader.call(@key), sources: Array(@source.select).compact)
          end

          emitted = publish_mode.publish(pctx, prefix: prefix)
          return emitted if emitted
          return nil unless built

          { kind: :built, value: { "key" => @key, "path" => Key::Path.resolve(pctx.manifest.data, self), "published_to" => [] } }
        end

        KIND = :derived

        def self.from_raw(common, raw)
          source = Parser.parse_source(raw, common[:key])
          raise UsageError.new("entry '#{common[:key]}' kind: derived needs source.from: project|command") unless source.kind == :derived

          new(source: source, events: raw["events"] || {}, **common)
        end

        Entry::REGISTRY[KIND] = self
      end
    end
  end
end
