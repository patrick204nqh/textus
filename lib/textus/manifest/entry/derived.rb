module Textus
  class Manifest
    class Entry
      class Derived < Base
        Projection = Data.define(:select, :pluck, :sort_by, :transform)
        External   = Data.define(:sources, :runner)

        attr_reader :source, :template, :inject_boot, :events

        def initialize(source:, template: nil, inject_boot: false, events: {}, **rest)
          super(**rest)
          @source = source
          @template = template
          @inject_boot = inject_boot
          @events = events || {}
        end

        def derived? = true
        def projection? = @source.is_a?(Projection)
        def external?   = @source.is_a?(External)

        def publish_via(pctx, prefix: nil) # rubocop:disable Lint/UnusedMethodArgument
          return nil unless in_generator_zone?

          target_path = Textus::Application::Writes::Materializer.new(
            ctx: pctx.ctx, manifest: pctx.manifest, file_store: pctx.file_store,
            bus: pctx.bus, root: pctx.root, store: pctx.store
          ).run(self)

          envelope = pctx.reader.call(@key)
          Array(publish_to).each do |rel|
            target_abs = File.join(pctx.repo_root, rel)
            Textus::Infra::Publisher.publish(source: target_path, target: target_abs, store_root: pctx.root)
            pctx.emit.call(:file_published, key: @key, envelope: envelope, source: target_path, target: target_abs)
          end

          src = @source
          selects = src.is_a?(Projection) ? Array(src.select).compact : []
          pctx.emit.call(:build_completed, key: @key, envelope: envelope, sources: selects)

          { kind: :built, value: { "key" => @key, "path" => target_path, "published_to" => publish_to } }
        end

        KIND = :derived

        def self.from_raw(common, raw)
          source = Parser.parse_source(raw, common[:key])
          new(
            source: source,
            template: raw["template"],
            inject_boot: raw["inject_boot"] == true,
            events: raw["events"] || {},
            **common,
          )
        end

        Entry::REGISTRY[KIND] = self
      end
    end
  end
end
