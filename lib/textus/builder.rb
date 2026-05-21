require "fileutils"

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
      published_leaves = publish_leaves(prefix: prefix)
      { "protocol" => Textus::PROTOCOL, "built" => built, "published_leaves" => published_leaves }
    end

    private

    def publish_leaves(prefix: nil)
      repo_root = File.dirname(@root)
      out = []
      @manifest.entries.each do |mentry|
        next unless mentry.nested && mentry.publish_each
        next if prefix && !mentry.key.start_with?(prefix) && !prefix.start_with?("#{mentry.key}.")

        @manifest.enumerate(prefix: mentry.key).each do |row|
          next unless row[:manifest_entry].equal?(mentry)
          next if prefix && !row[:key].start_with?(prefix) && row[:key] != prefix

          target_rel = mentry.publish_target_for(row[:key])
          target_abs = File.expand_path(File.join(repo_root, target_rel))
          unless target_abs.start_with?(File.expand_path(repo_root) + File::SEPARATOR)
            raise PublishError.new(
              "entry '#{mentry.key}': publish_each target '#{target_rel}' for key '#{row[:key]}' escapes repo root",
            )
          end

          Publisher.publish(source: row[:path], target: target_abs, store_root: @root)
          out << { "key" => row[:key], "source" => row[:path], "target" => target_abs }
        end
      end
      out
    end

    def derived_zone?(mentry)
      writers = @manifest.zone_writers(mentry.zone)
      writers.include?("build")
    end

    def materialize(mentry)
      target_path = Pipeline.run(
        store: @store,
        mentry: mentry,
        template_loader: ->(name) { read_template(name) },
      )
      publish_and_fire(mentry, target_path)
      { "key" => mentry.key, "path" => target_path, "published_to" => mentry.publish_to }
    end

    def read_template(name)
      tpl_path = File.join(@root, "templates", name)
      raise TemplateError.new("template not found: #{tpl_path}", template_name: name) unless File.exist?(tpl_path)

      File.read(tpl_path)
    end

    def publish_and_fire(mentry, target_path)
      mentry.publish_to.each do |rel|
        repo_root = File.dirname(@root)
        Publisher.publish(source: target_path, target: File.join(repo_root, rel), store_root: @root)
      end

      envelope = @store.get(mentry.key)
      @store.fire_event(:build, key: mentry.key, envelope: envelope,
                                sources: Array(mentry.projection&.fetch("select", nil)).compact)
    end
  end
end
