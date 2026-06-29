module Textus
  module Handlers
    module Read
      class GetEntry
        def initialize(container:, freshness_evaluator:)
          @container = container
          @freshness_evaluator = freshness_evaluator
        end

        def call(command, _call)
          envelope = Store::Entry::Reader.from(container: @container).read(command.key)
          return Value::Result.failure(:not_found, "no entry at #{command.key}") unless envelope

          envelope = expand_sources(envelope, depth: 0)
          Value::Result.success(envelope.with(freshness: @freshness_evaluator.verdict(resolve_entry(command.key))))
        end

        MAX_SOURCE_DEPTH = 5

        private

        def expand_sources(envelope, depth:)
          return envelope if depth >= MAX_SOURCE_DEPTH

          raw_sources = Array(envelope.meta["sources"])
          return envelope if raw_sources.empty?

          expanded = raw_sources.map { |src| expand_one_source(src, depth: depth) }
          envelope.with(sources: expanded)
        end

        def expand_one_source(src, depth:)
          src = { "key" => src } if src.is_a?(String)
          return src unless src.is_a?(Hash) && src["key"].is_a?(String)

          key = src["key"]
          stored_etag = src["etag"]
          current_etag = resolve_current_etag(key)
          suspended = stored_etag && current_etag ? stored_etag != current_etag : false

          result = src.merge("suspended" => suspended)

          child_env = @container.reader.read(key)
          if child_env
            child_expanded = expand_sources(child_env, depth: depth + 1)
            child_sources = Array(child_expanded.sources)
            result = result.merge("sources" => child_sources) unless child_sources.empty?
          end

          result
        end

        def resolve_current_etag(key)
          path = @container.manifest.resolver.resolve(key).path
          return nil unless @container.file_store.exists?(path)

          @container.file_store.etag(path)
        rescue Textus::Error
          nil
        end

        def resolve_entry(key)
          @container.manifest.resolver.resolve(key).entry
        end
      end
    end
  end
end
