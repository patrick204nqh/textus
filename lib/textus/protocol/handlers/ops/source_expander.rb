module Textus
  module Protocol
    module Handlers
      module Ops
        class SourceExpander
          def call(env, ctx:, depth: 0)
            return env if depth >= 5

            raw_sources = Array(env.meta["sources"])
            return env if raw_sources.empty?

            expanded = raw_sources.map { |src| expand_one(src, ctx:, depth:) }
            env.with(sources: expanded)
          end

          private

          def expand_one(src, ctx:, depth:)
            src = { "key" => src } if src.is_a?(String)
            return src unless src.is_a?(Hash) && src["key"].is_a?(String)

            key = src["key"]
            stored_etag = src["etag"]
            res = ctx.resolve(key:)
            path = res.path
            current_etag = File.exist?(path) ? ctx.file_system.etag(path) : nil
            suspended = stored_etag && current_etag ? stored_etag != current_etag : false
            result = src.merge("suspended" => suspended)
            child_env = ctx.read(key:)
            if child_env
              child_expanded = call(child_env, ctx:, depth: depth + 1)
              child_sources = Array(child_expanded.sources)
              result = result.merge("sources" => child_sources) unless child_sources.empty?
            end
            result
          end
        end
      end
    end
  end
end
