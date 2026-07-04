module Textus
  module Protocol
    module Handlers
      module Read
        include Concern
        extend self

        def get(key:, store:, ctx:, call:)
          env = store.read(key)
          unless env
            suggestions = ctx.manifest.resolver.suggestions_for(key)
            raise Textus::UnknownKey.new(key, suggestions:)
          end

          expand_sources(env, store, depth: 0).to_h_for_wire
        end

        def list(store:, ctx:, call:, prefix: nil, lane: nil, q: nil, schema: nil)
          store.list(prefix:, lane:, q:, schema:)
        end

        def where(key:, store:, ctx:, call:)
          res = store.resolve(key)
          { "protocol" => Textus::PROTOCOL, "key" => key, "lane" => res.entry.lane, "path" => res.path }
        end

        def uid(key:, store:, ctx:, call:)
          env = store.read(key)
          raise Textus::UnknownKey.new(key) unless env

          env.uid
        end

        def deps(key:, store:, ctx:, call:)
          entry = ctx.manifest.data.entries.find { |e| e.key == key }
          deps_list = entry&.external? ? Array(entry.source&.sources).compact : []
          { "key" => key, "deps" => deps_list.uniq }
        end

        def rdeps(key:, store:, ctx:, call:)
          source_rdeps = ctx.manifest.data.entries.each_with_object([]) do |entry, acc|
            next unless entry.external?

            sources = Array(entry.source&.sources).compact
            acc << entry.key if sources.any? { |s| s == key || key.start_with?("#{s}.") }
          end
          link_rdeps = store.link_store.links_to(key)
          { "key" => key, "rdeps" => (source_rdeps + link_rdeps).uniq.sort }
        end

        def graph(key:, store:, ctx:, call:, depth: nil)
          from = store.link_store.links_from(key)
          to   = store.link_store.links_to(key)
          { "key" => key, "neighbors" => (from + to).uniq.sort,
            "reachable" => store.link_store.reachable(from: key, depth:).sort }
        end

        def schema_show(key:, store:, ctx:, call:)
          mentry = store.mentry_for(key)
          schema = ctx.schemas.fetch_or_nil(mentry.schema)
          { "protocol" => Textus::PROTOCOL, "key" => key,
            "schema_ref" => mentry.schema, "schema" => schema&.to_h }
        end

        private

        def expand_sources(envelope, store, depth:)
          return envelope if depth >= 5

          raw_sources = Array(envelope.meta["sources"])
          return envelope if raw_sources.empty?

          expanded = raw_sources.map { |src| expand_one_source(src, store, depth:) }
          envelope.with(sources: expanded)
        end

        def expand_one_source(src, store, depth:)
          src = { "key" => src } if src.is_a?(String)
          return src unless src.is_a?(Hash) && src["key"].is_a?(String)

          key = src["key"]
          stored_etag = src["etag"]
          res = store.resolve(key)
          path = res.path
          current_etag = store.file_system.exists?(path) ? store.file_system.etag(path) : nil
          suspended = stored_etag && current_etag ? stored_etag != current_etag : false
          result = src.merge("suspended" => suspended)
          child_env = store.read(key)
          if child_env
            child_expanded = expand_sources(child_env, store, depth: depth + 1)
            child_sources = Array(child_expanded.sources)
            result = result.merge("sources" => child_sources) unless child_sources.empty?
          end
          result
        end

        def key_in_lane?(key, lane_name, store)
          mentry = store.mentry_for(key)
          mentry && mentry.lane == lane_name
        rescue Textus::Error
          false
        end
      end
    end
  end
end
