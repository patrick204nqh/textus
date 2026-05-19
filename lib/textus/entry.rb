require "yaml"

module Textus
  # Parses and serializes Markdown files with YAML frontmatter.
  module Entry
    SEP = "---".freeze

    def self.parse(raw, path: nil)
      raw = raw.dup.force_encoding(Encoding::UTF_8)
      raise BadFrontmatter.new(path, "entry is not valid UTF-8") unless raw.valid_encoding?
      return { "frontmatter" => {}, "body" => raw } unless raw.start_with?("---\n") || raw.start_with?("---\r\n")

      lines = raw.split(/\r?\n/, -1)
      # lines[0] == "---"
      close_idx = lines[1..].index("---")
      raise BadFrontmatter.new(path, "frontmatter not terminated") unless close_idx

      close_idx += 1
      fm_yaml = lines[1...close_idx].join("\n")
      body = lines[(close_idx + 1)..].join("\n")
      begin
        fm = fm_yaml.strip.empty? ? {} : YAML.safe_load(fm_yaml, permitted_classes: [Date, Time], aliases: false)
      rescue Psych::SyntaxError => e
        raise BadFrontmatter.new(path, "YAML parse failed: #{e.message}")
      end
      fm = {} unless fm.is_a?(Hash)
      { "frontmatter" => fm, "body" => body }
    end

    def self.serialize(frontmatter:, body:)
      fm_yaml = frontmatter.empty? ? "" : YAML.dump(frontmatter).sub(/\A---\n/, "")
      body = body.to_s
      body += "\n" unless body.empty? || body.end_with?("\n")
      "---\n#{fm_yaml}---\n#{body}"
    end
  end
end
