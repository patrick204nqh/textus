# frozen_string_literal: true

module Textus
  module Links
    class UriRewriter
      # Matches Markdown links with a textus: URI, with optional #anchor.
      # Group 1: link text, Group 2: key, Group 3: anchor (may be nil/empty)
      TEXTUS_URI = /\[([^\]]*)\]\(textus:([^#)\s]+)(#[^)\s]*)?\)/

      def initialize(resolver:, from_path:)
        @resolver  = resolver
        @from_path = from_path
      end

      def rewrite(content)
        content.gsub(TEXTUS_URI) do
          text   = Regexp.last_match(1)
          key    = Regexp.last_match(2)
          anchor = Regexp.last_match(3).to_s

          resolved = @resolver.resolve(key: key, from_path: @from_path)
          "[#{text}](#{resolved}#{anchor})"
        rescue Textus::Links::Resolver::UnknownKeyError
          "[#{text}](`textus get #{key}`)"
        end
      end
    end
  end
end
