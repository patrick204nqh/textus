module Textus
  module Dependencies
    def self.deps_of(manifest, key)
      entry = manifest.entries.find { |e| e.key == key } or return []
      result = []
      Array(entry.projection&.fetch("select", nil)).each { |s| result << s }
      Array(entry.generator&.fetch("sources", nil)).each { |s| result << s }
      result.uniq
    end

    def self.rdeps_of(manifest, key)
      manifest.entries.each_with_object([]) do |e, acc|
        sources = Array(e.projection&.fetch("select", nil)) + Array(e.generator&.fetch("sources", nil))
        acc << e.key if sources.any? { |s| s == key || key.start_with?("#{s}.") }
      end
    end

    def self.published_of(manifest)
      manifest.entries.reject { |e| e.publish_to.empty? }.map do |e|
        { "key" => e.key, "publish_to" => e.publish_to }
      end
    end
  end
end
