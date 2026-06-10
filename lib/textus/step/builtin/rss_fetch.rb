# frozen_string_literal: true

require "rexml/document"
require "yaml"

module Textus
  module Step
    module Builtin
      class RssFetch < Step::Fetch
        step_name "rss"
        def call(config:, args:, **)
          _ = args
          doc = REXML::Document.new(config["bytes"].to_s)
          items = doc.elements.to_a("//item").map do |item|
            {
              "title" => item.elements["title"]&.text,
              "link" => item.elements["link"]&.text,
              "pubDate" => item.elements["pubDate"]&.text,
            }
          end
          { _meta: {}, body: YAML.dump(items) }
        end
      end
    end
  end
end
