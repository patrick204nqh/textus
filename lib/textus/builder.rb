require "fileutils"
require "json"
require "time"
require "yaml"

module Textus
  class Builder
    def initialize(store)
      @store = store
      @manifest = store.manifest
      @root = store.root
    end

    def build(prefix: nil)
      built = []
      @manifest.entries.each do |mentry|
        next unless derived_zone?(mentry)
        next unless mentry.projection || mentry.template
        next if prefix && !mentry.key.start_with?(prefix)

        result = materialize(mentry)
        built << result
      end
      { "protocol" => Textus::PROTOCOL, "built" => built }
    end

    private

    def derived_zone?(mentry)
      writers = @manifest.zone_writers(mentry.zone)
      writers.include?("build")
    end

    def materialize(mentry)
      data =
        if mentry.projection
          Projection.new(@store, mentry.projection).run
        else
          { "entries" => [], "count" => 0, "generated_at" => Time.now.utc.iso8601 }
        end

      bytes =
        case mentry.format
        when "markdown" then build_markdown(mentry, data)
        when "text"     then build_text(mentry, data)
        when "json"     then build_structured(mentry, data, "json")
        when "yaml"     then build_structured(mentry, data, "yaml")
        else raise UsageError.new("builder: unsupported format #{mentry.format.inspect} for '#{mentry.key}'")
        end

      target_path = File.join(@root, "zones", mentry.path)
      FileUtils.mkdir_p(File.dirname(target_path))
      File.binwrite(target_path, bytes)

      publish_and_fire(mentry, target_path)
      { "key" => mentry.key, "path" => target_path, "published_to" => mentry.publish_to }
    end

    # Markdown: projection -> template -> markdown.serialize(frontmatter, body).
    # Frontmatter carries the legacy `generated:` bookkeeping block. Per plan-1.2 §6,
    # `_meta` ordering applies to structured formats only; markdown keeps existing shape
    # for backward compat with consumers reading frontmatter["generated"]["at"].
    def build_markdown(mentry, data)
      body = render_template!(mentry, data)
      frontmatter = {
        "generated" => {
          "at" => Time.now.utc.iso8601,
          "from" => Array(mentry.projection&.fetch("select", nil)).compact,
        },
      }
      Entry.for_format("markdown").serialize(frontmatter: frontmatter, body: body)
    end

    # Text: projection -> template -> text.serialize(body). No frontmatter, no _meta.
    def build_text(mentry, data)
      body = render_template!(mentry, data)
      Entry.for_format("text").serialize(frontmatter: {}, body: body)
    end

    # JSON / YAML pipeline. Templateless = default; template = escape hatch.
    def build_structured(mentry, data, format)
      strategy = Entry.for_format(format)

      content =
        if mentry.template
          parse_rendered_template!(mentry, data, format)
        else
          # Default rule: if the reducer returned a Hash (it replaced `rows`), use it as-is.
          # Otherwise wrap the entries list as { "entries" => [...] } so the top level is a Hash
          # (required to carry _meta).
          if mentry.projection && mentry.projection["reducer"] && data.is_a?(Hash) && !data.key?("entries")
            data
          elsif data.is_a?(Hash) && data["entries"].is_a?(Array)
            { "entries" => data["entries"] }
          else
            data.is_a?(Hash) ? data : { "entries" => Array(data) }
          end
        end

      final = inject_meta(content, mentry)
      strategy.serialize(frontmatter: {}, body: "", content: final)
    end

    def render_template!(mentry, data)
      raise TemplateError.new("entry '#{mentry.key}': #{mentry.format} build requires a template") unless mentry.template

      tpl_path = File.join(@root, "templates", mentry.template)
      raise TemplateError.new("template not found: #{tpl_path}") unless File.exist?(tpl_path)

      Mustache.render(File.read(tpl_path), data)
    end

    def parse_rendered_template!(mentry, data, format)
      tpl_path = File.join(@root, "templates", mentry.template)
      raise TemplateError.new("template not found: #{tpl_path}") unless File.exist?(tpl_path)

      rendered = Mustache.render(File.read(tpl_path), data)
      begin
        parsed =
          case format
          when "json" then ::JSON.parse(rendered)
          when "yaml" then ::YAML.safe_load(rendered, permitted_classes: [Date, Time], aliases: false)
          end
      rescue ::JSON::ParserError, Psych::SyntaxError, Psych::DisallowedClass, Psych::AliasesNotEnabled => e
        raise BadRender.new("entry '#{mentry.key}': template did not render valid #{format}: #{e.message}")
      end
      raise BadRender.new("entry '#{mentry.key}': template must render a top-level object/mapping") unless parsed.is_a?(Hash)

      parsed
    end

    # Builds the _meta block per §6 ordering and inserts it as the first top-level key.
    def inject_meta(content_hash, mentry)
      meta = {}
      meta["generated_at"] = Time.now.utc.iso8601
      from = Array(mentry.projection&.fetch("select", nil)).compact
      meta["from"] = from unless from.empty?
      meta["template"] = mentry.template if mentry.template
      reducer = mentry.projection&.dig("reducer")
      meta["reducer"] = reducer if reducer

      # Rebuild so _meta appears first; user content follows.
      out = { "_meta" => meta }
      content_hash.each { |k, v| out[k] = v unless k == "_meta" }
      out
    end

    def publish_and_fire(mentry, target_path)
      mentry.publish_to.each do |rel|
        repo_root = File.dirname(@root)
        Symlink.publish(source: target_path, target: File.join(repo_root, rel))
      end

      envelope = @store.get(mentry.key)
      @store.fire_event(:build, key: mentry.key, envelope: envelope,
                                sources: Array(mentry.projection&.fetch("select", nil)).compact)
    end
  end
end
