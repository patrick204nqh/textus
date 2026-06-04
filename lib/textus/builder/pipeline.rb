require "fileutils"

module Textus
  module Builder
    module InjectMeta
      # Returns a new hash with _meta as the first key, per SPEC §6 ordering.
      # Carries only deterministic provenance (`from`/`reduce`/`template`) — the
      # volatile `generated_at` is deliberately NOT stamped, so the built
      # artifact is content-addressed and a rebuild is a byte-for-byte no-op
      # (ADR 0070). Build time lives out of the tracked artifact.
      def self.call(content_hash, mentry)
        meta = {}
        if mentry.is_a?(Textus::Manifest::Entry::Derived)
          src = mentry.source
          if src.is_a?(Textus::Manifest::Entry::Derived::Projection)
            from = Array(src.select).compact
            meta["from"] = from unless from.empty?
            meta["reduce"] = src.transform if src.transform
          end
        end
        meta["template"] = mentry.template if mentry.template

        out = { "_meta" => meta }
        content_hash.each { |k, v| out[k] = v unless k == "_meta" }
        out
      end
    end

    module Pipeline
      Deps = Data.define(
        :manifest, :reader, :lister, :rpc, :template_loader, :transform_context, :inject_boot
      )

      def self.renderers
        @renderers ||= {
          "markdown" => Renderer::Markdown,
          "text" => Renderer::Text,
          "json" => Renderer::Json,
          "yaml" => Renderer::Yaml,
        }
      end

      def self.run(mentry:, deps:)
        # 1. Load sources + project + reduce. Only projection-derived entries are
        # buildable in-process; External entries are generated out-of-band and are
        # filtered out upstream (Derived#publish_via), so reaching here with a
        # non-projection source is a wiring bug — fail loudly rather than emit an
        # empty payload (and never re-stamp the volatile generated_at, ADR 0070).
        unless mentry.is_a?(Textus::Manifest::Entry::Derived) && mentry.projection?
          raise UsageError.new(
            "builder: '#{mentry.key}' is not a projection-derived entry; only projections are buildable",
          )
        end

        data =
          Textus::Projection.new(
            reader: deps.reader,
            spec: mentry.source.to_h.transform_keys(&:to_s),
            lister: deps.lister,
            rpc: deps.rpc,
            transform_context: deps.transform_context,
          ).run
        data = data.merge("boot" => deps.inject_boot.call) if mentry.inject_boot && deps.inject_boot

        # 2. Render
        klass = renderers[mentry.format] or
          raise UsageError.new("builder: unsupported format #{mentry.format.inspect} for '#{mentry.key}'")
        bytes = klass.new(template_loader: deps.template_loader).call(mentry: mentry, data: data)

        # 3. Write (idempotent: skip if only generated_at would differ)
        target_path = Key::Path.resolve(deps.manifest.data, mentry)
        FileUtils.mkdir_p(File.dirname(target_path))
        write_if_changed(target_path, bytes, mentry.format)

        target_path
      end

      # Built artifacts are content-addressed (no volatile timestamp, ADR 0070),
      # so identity is plain byte-equality: skip the write when nothing changed.
      # `format` is retained for signature stability across renderers.
      def self.write_if_changed(target_path, bytes, _format)
        return if File.exist?(target_path) && File.binread(target_path) == bytes

        File.binwrite(target_path, bytes)
      end
    end
  end
end
