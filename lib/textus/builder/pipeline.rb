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

    # Replaces the freshly-stamped timestamp inside `new_bytes` with the
    # timestamp pulled from `old_bytes` (same format). Returns the rewritten
    # bytes, or nil if either side lacks a parseable timestamp.
    module IdempotentWrite
      def self.rewrite_with_prior_timestamp(new_bytes:, old_bytes:, format:)
        prior = extract_timestamp(old_bytes, format)
        fresh = extract_timestamp(new_bytes, format)
        return nil unless prior && fresh
        return new_bytes if prior == fresh

        new_bytes.sub(fresh, prior)
      end

      def self.extract_timestamp(bytes, format)
        case format
        when "markdown"
          parsed = Entry.for_format("markdown").parse(bytes)
          parsed.dig("_meta", "generated", "at")
        when "json", "yaml"
          parsed = Entry.for_format(format).parse(bytes)
          parsed.dig("_meta", "generated_at")
        else # rubocop:disable Style/EmptyElse
          nil
        end
      rescue Textus::BadFrontmatter
        nil
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
            ops = Operations.for(store)
            Projection.new(
              reader: ops.reads.get.method(:call),
              spec: mentry.projection,
              lister: ops.reads.list.method(:call),
              transform_resolver: ->(name) { store.registry.rpc_callable(:transform_rows, name) },
              transform_context: Application::Context.system(store),
            ).run
          else
            { "entries" => [], "count" => 0, "generated_at" => Time.now.utc.iso8601 }
          end
        data = data.merge("intro" => Intro.run(store)) if mentry.inject_intro

        # 2. Render
        klass = renderers[mentry.format] or
          raise UsageError.new("builder: unsupported format #{mentry.format.inspect} for '#{mentry.key}'")
        bytes = klass.new(template_loader: template_loader).call(mentry: mentry, data: data)

        # 3. Write (idempotent: skip if only generated_at would differ)
        target_path = Key::Path.resolve(store.manifest, mentry)
        FileUtils.mkdir_p(File.dirname(target_path))
        write_if_changed(target_path, bytes, mentry.format)

        target_path
      end

      def self.write_if_changed(target_path, bytes, format)
        if File.exist?(target_path)
          old_bytes = File.binread(target_path)
          if format == "text"
            return if old_bytes == bytes
          else
            rewritten = IdempotentWrite.rewrite_with_prior_timestamp(
              new_bytes: bytes, old_bytes: old_bytes, format: format,
            )
            return if rewritten && rewritten == old_bytes
          end
        end
        File.binwrite(target_path, bytes)
      end
    end
  end
end
