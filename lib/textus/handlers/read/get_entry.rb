module Textus
  module Handlers
    module Read
      module GetEntry
        HANDLES = Dispatch::Contracts::GetEntry
        NEEDS   = %i[file_store manifest layout freshness_evaluator].freeze

        MAX_SOURCE_DEPTH = 5

        def self.call(command, _call, deps)
          reader = Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout)
          envelope = reader.read(command.key)
          return Value::Result.failure(:not_found, "no entry at #{command.key}") unless envelope

          envelope = expand_sources(envelope, depth: 0, deps: deps)
          Value::Result.success(envelope.with(freshness: deps.freshness_evaluator.verdict(resolve_entry(command.key, deps: deps))))
        end

        def self.expand_sources(envelope, depth:, deps:)
          return envelope if depth >= MAX_SOURCE_DEPTH

          raw_sources = Array(envelope.meta["sources"])
          return envelope if raw_sources.empty?

          expanded = raw_sources.map { |src| expand_one_source(src, depth: depth, deps: deps) }
          envelope.with(sources: expanded)
        end

        def self.expand_one_source(src, depth:, deps:)
          src = { "key" => src } if src.is_a?(String)
          return src unless src.is_a?(Hash) && src["key"].is_a?(String)

          key = src["key"]
          stored_etag = src["etag"]
          current_etag = resolve_current_etag(key, deps: deps)
          suspended = stored_etag && current_etag ? stored_etag != current_etag : false

          result = src.merge("suspended" => suspended)

          child_env = resolve_env(key, deps: deps)
          if child_env
            child_expanded = expand_sources(child_env, depth: depth + 1, deps: deps)
            child_sources = Array(child_expanded.sources)
            result = result.merge("sources" => child_sources) unless child_sources.empty?
          end

          result
        end

        def self.resolve_current_etag(key, deps:)
          path = deps.manifest.resolver.resolve(key).path
          return nil unless deps.file_store.exists?(path)

          deps.file_store.etag(path)
        rescue Textus::Error
          nil
        end

        def self.resolve_entry(key, deps:)
          deps.manifest.resolver.resolve(key).entry
        end

        def self.resolve_env(key, deps:)
          Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout).read(key)
        end
      end
    end
  end
end
