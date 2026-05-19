require "fileutils"
require "time"

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
          { "entries" => [] }
        end

      body =
        if mentry.template
          tpl_path = File.join(@root, "templates", mentry.template)
          raise TemplateError.new("template not found: #{tpl_path}") unless File.exist?(tpl_path)

          Mustache.render(File.read(tpl_path), data)
        else
          format_default(data)
        end

      target_path = File.join(@root, "zones", mentry.path)
      FileUtils.mkdir_p(File.dirname(target_path))
      frontmatter = {
        "generated" => {
          "at" => Time.now.utc.iso8601,
          "from" => Array(mentry.projection&.fetch("select", nil)).compact,
        },
      }
      bytes = Entry.serialize(frontmatter: frontmatter, body: body)
      File.binwrite(target_path, bytes)

      mentry.publish_to.each do |rel|
        repo_root = File.dirname(@root)
        Symlink.publish(source: target_path, target: File.join(repo_root, rel))
      end

      { "key" => mentry.key, "path" => target_path, "published_to" => mentry.publish_to }
    end

    def format_default(data)
      data["entries"].map { |e| "- " + (e["name"] || e["_key"]).to_s }.join("\n") + "\n"
    end
  end
end
