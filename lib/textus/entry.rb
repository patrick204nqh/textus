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

    def self.for_format(format)
      STRATEGIES.fetch(format.to_s) { raise UsageError.new("unknown entry format: #{format.inspect}") }
    end

    def self.parse(raw, path: nil, format: "markdown")
      for_format(format).parse(raw, path: path)
    end

    def self.serialize(meta: {}, body: "", content: nil, format: "markdown")
      for_format(format).serialize(meta: meta, body: body, content: content)
    end
  end
end
