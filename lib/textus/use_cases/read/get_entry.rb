module Textus
  module UseCases
    module Read
      class GetEntry < Base
        handles Dispatch::Contracts::GetEntry
        needs :entry_store, :manifest, :file_system

        def call
          envelope = @entry_store.read(@command.key)
          return failure(:not_found, "no entry at #{@command.key}") unless envelope

          envelope = expand_sources(envelope, depth: 0)
          success(envelope)
        end

        private

        def expand_sources(envelope, depth:)
          return envelope if depth >= 5

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

          child_env = resolve_env(key)
          if child_env
            child_expanded = expand_sources(child_env, depth: depth + 1)
            child_sources = Array(child_expanded.sources)
            result = result.merge("sources" => child_sources) unless child_sources.empty?
          end

          result
        end

        def resolve_current_etag(key)
          path = @manifest.resolver.resolve(key).path
          return nil unless @file_system.exists?(path)

          @file_system.etag(path)
        rescue Textus::Error
          nil
        end

        def resolve_env(key)
          @entry_store.read(key)
        end
      end
    end
  end
end
