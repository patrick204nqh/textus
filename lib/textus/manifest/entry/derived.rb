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

        def publish_via(pctx, prefix: nil) # rubocop:disable Lint/UnusedMethodArgument
          # Derived entries always build data here; external ones are skipped below.
          # External entries are produced by an out-of-band runner — textus has
          # no in-process runner. The build path only tracks their staleness
          # (Domain::Staleness::GeneratorCheck); building here would clobber
          # the runner's artifact with an empty payload. Skip the build entirely.
          return nil if external?

          target_path = Textus::Write::DataBuilder.new(
            container: pctx.container, call: pctx.call,
          ).run(self)

          envelope = pctx.reader.call(@key)
          Array(publish_to).each do |rel|
            target_abs = File.join(pctx.repo_root, rel)
            Textus::Ports::Publisher.publish(source: target_path, target: target_abs, store_root: pctx.root)
            pctx.emit(:entry_published, key: @key, envelope: envelope, source: target_path, target: target_abs)
          end

          selects = @source.projection? ? Array(@source.select).compact : []
          pctx.emit(:entry_produced, key: @key, envelope: envelope, sources: selects)

          { kind: :built, value: { "key" => @key, "path" => target_path, "published_to" => publish_to } }
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
