module Textus
  module Entry
    # Plain-text entry storage. No frontmatter or structured content.
    class Text < Base
      def self.parse(raw, path: nil)
        raw = raw.dup.force_encoding(Encoding::UTF_8)
        raise BadFrontmatter.new(path, "entry is not valid UTF-8") unless raw.valid_encoding?

        { "_meta" => {}, "body" => raw, "content" => nil }
      end

      def self.serialize(meta:, body:, content: nil)
        _ = meta
        _ = content
        b = body.to_s
        b += "\n" unless b.empty? || b.end_with?("\n")
        b
      end

      def self.extensions = [".txt"]
    end
  end
end
