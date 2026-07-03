module Textus
  module Protocol
    class Links
      class UriRewriter
        TEXTUS_URI = /\[([^\]]*)\]\(textus:([^#)\s]+)(#[^)\s]*)?\)/

        def initialize(resolver:, from_path:, from_key: nil, edge_store: nil)
          @resolver   = resolver
          @from_path  = from_path
          @from_key   = from_key
          @edge_store = edge_store
        end

        def rewrite(content)
          content.gsub(TEXTUS_URI) do
            text   = Regexp.last_match(1)
            key    = Regexp.last_match(2)
            anchor = Regexp.last_match(3).to_s

            resolved = @resolver.resolve(key: key, from_path: @from_path)
            @edge_store&.record(from_key: @from_key, to_key: key)
            "[#{text}](#{resolved}#{anchor})"
          rescue Resolver::UnknownKeyError
            "[#{text}](`textus get #{key}`)"
          end
        end
      end
    end
  end
end
