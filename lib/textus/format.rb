module Textus
  module Format
    SEP = "---".freeze

    STRATEGIES = {
      "markdown" => -> { Format::Markdown },
      "json" => -> { Format::Json },
      "yaml" => -> { Format::Yaml },
      "text" => -> { Format::Text },
    }.freeze

    # Optional registry for injectable format strategies. Tests or app
    # initializers can set Format.registry = { "custom" => -> { MyFormat }}
    @registry = nil

    def self.registry=(reg)
      @registry = reg
    end

    def self.registry
      @registry
    end

    EXT_TO_FORMAT = {
      ".md" => "markdown",
      ".json" => "json",
      ".yaml" => "yaml",
      ".yml" => "yaml",
      ".txt" => "text",
    }.freeze

    def self.for(format)
      key = format.to_s
      return registry.fetch(key).call if registry&.key?(key)

      STRATEGIES.fetch(key) { raise Textus::UsageError.new("unknown entry format: #{format.inspect}") }.call
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

    def self.data_to_payload(data, format)
      return { meta: {}, body: "", content: nil } if data.nil?

      Format.for(format).data_to_payload(data)
    end
  end
end
