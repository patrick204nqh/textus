# frozen_string_literal: true

require "yaml"

module Textus
  module Step
    module Builtin
      class MarkdownLinksFetch < Step::Fetch
        step_name "markdown-links"
        def call(config:, args:, **)
          _ = args
          links = config["bytes"].to_s.scan(%r{\[([^\]]+)\]\((https?://[^)\s]+)\)}).map do |text, href|
            { "text" => text, "href" => href }
          end
          { _meta: {}, body: YAML.dump(links) }
        end
      end
    end
  end
end
