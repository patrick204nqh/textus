require "fileutils"
require "time"

module Textus
  module Builder
    module InjectMeta
      # Returns a new hash with _meta as the first key, per SPEC §6 ordering.
      def self.call(content_hash, mentry)
        meta = { "generated_at" => Time.now.utc.iso8601 }
        from = Array(mentry.projection&.fetch("select", nil)).compact
        meta["from"] = from unless from.empty?
        meta["template"] = mentry.template if mentry.template
        reduce = mentry.projection&.dig("transform")
        meta["reduce"] = reduce if reduce

        out = { "_meta" => meta }
        content_hash.each { |k, v| out[k] = v unless k == "_meta" }
        out
      end
    end

    module Pipeline
      def self.renderers
        @renderers ||= {
          "markdown" => Renderer::Markdown,
          "text" => Renderer::Text,
          "json" => Renderer::Json,
          "yaml" => Renderer::Yaml,
        }
      end

      def self.run(store:, mentry:, template_loader:)
        # 1. Load sources + project + reduce
        data =
          if mentry.projection
            Projection.new(store, mentry.projection).run
          else
            { "entries" => [], "count" => 0, "generated_at" => Time.now.utc.iso8601 }
          end
        data = data.merge("intro" => Intro.run(store)) if mentry.inject_intro

        # 2. Render
        klass = renderers[mentry.format] or
          raise UsageError.new("builder: unsupported format #{mentry.format.inspect} for '#{mentry.key}'")
        bytes = klass.new(template_loader: template_loader).call(mentry: mentry, data: data)

        # 3. Write
        target_path = Key::Path.resolve(store.manifest, mentry)
        FileUtils.mkdir_p(File.dirname(target_path))
        File.binwrite(target_path, bytes)

        target_path
      end
    end
  end
end
