module Textus
  # Public entry-format dispatcher.
  module Entry
    SEP = "---".freeze

    STRATEGIES = {
      "markdown" => Markdown,
      "json" => Json,
      "yaml" => Yaml,
      "text" => Text,
    }.freeze

    EXT_TO_FORMAT = {
      ".md" => "markdown",
      ".json" => "json",
      ".yaml" => "yaml",
      ".yml" => "yaml",
      ".txt" => "text",
    }.freeze

    def self.for_format(format)
      STRATEGIES.fetch(format.to_s) { raise UsageError.new("unknown entry format: #{format.inspect}") }
    end

    def self.infer_from_extension(ext)
      EXT_TO_FORMAT[ext]
    end

    def self.formats
      EXT_TO_FORMAT.values.uniq
    end

    def self.parse(raw, path: nil, format: "markdown")
      for_format(format).parse(raw, path: path)
    end

    def self.serialize(meta: {}, body: "", content: nil, format: "markdown")
      for_format(format).serialize(meta: meta, body: body, content: content)
    end
  end
end
