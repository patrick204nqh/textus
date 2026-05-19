module Textus
  module Entry
    # Plain-text entry storage. No frontmatter or structured content.
    module Text
      def self.parse(raw, path: nil)
        raw = raw.dup.force_encoding(Encoding::UTF_8)
        raise BadFrontmatter.new(path, "entry is not valid UTF-8") unless raw.valid_encoding?

        { "frontmatter" => {}, "body" => raw, "content" => nil }
      end

      def self.serialize(frontmatter:, body:, content: nil)
        _ = frontmatter
        _ = content
        b = body.to_s
        b += "\n" unless b.empty? || b.end_with?("\n")
        b
      end

      def self.extensions = [".txt"]
    end
  end
end
