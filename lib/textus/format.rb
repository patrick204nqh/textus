module Textus
  module Format
    SEP = "---".freeze

    STRATEGIES = {
      "markdown" => -> { Format::Markdown },
      "json" => -> { Format::Json },
      "yaml" => -> { Format::Yaml },
      "text" => -> { Format::Text },
    }.freeze

    EXT_TO_FORMAT = {
      ".md" => "markdown",
      ".json" => "json",
      ".yaml" => "yaml",
      ".yml" => "yaml",
      ".txt" => "text",
    }.freeze

    def self.for(format)
      STRATEGIES.fetch(format.to_s) { raise Textus::UsageError.new("unknown entry format: #{format.inspect}") }.call
    end

    def self.infer_from_extension(ext)
      EXT_TO_FORMAT[ext]
    end

    def self.formats
      EXT_TO_FORMAT.values.uniq
    end

    def self.parse(raw, path: nil, format: "markdown")
      Format.for(format).parse(raw, path: path)
    end

    def self.serialize(meta: {}, body: "", content: nil, format: "markdown")
      Format.for(format).serialize(meta: meta, body: body, content: content)
    end
  end
end
