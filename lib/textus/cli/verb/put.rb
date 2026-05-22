module Textus
  class CLI
    class Verb
      class Put < Verb
        option :as_flag, "--as=ROLE"
        option :use_stdin, "--stdin"
        option :fetch_name, "--fetch=NAME"

        def call(store) # rubocop:disable Metrics/AbcSize
          key = positional.shift or raise UsageError.new("put requires a key")
          raise UsageError.new("put requires --stdin in v1") unless use_stdin

          role = Role.resolve(flag: as_flag, env: ENV, root: store.root)

          raw = @stdin.read
          payload =
            if fetch_name
              callable = store.registry.rpc_callable(:intake, fetch_name)
              result =
                begin
                  Timeout.timeout(Textus::Application::Refresh::Worker::FETCH_TIMEOUT_SECONDS) do
                    callable.call(config: { "bytes" => raw }, store: Textus::Store::View.new(store), args: {})
                  end
                rescue Timeout::Error
                  raise UsageError.new(
                    "fetch '#{fetch_name}' exceeded #{Textus::Application::Refresh::Worker::FETCH_TIMEOUT_SECONDS}s timeout",
                  )
                end
              basename = key.split(".").last
              {
                "_meta" => {
                  "name" => basename,
                  "last_refreshed_at" => Time.now.utc.iso8601,
                  "fetched_with" => fetch_name,
                }.merge(result[:_meta] || result["_meta"] || result[:frontmatter] || result["frontmatter"] || {}),
                "body" => result[:body] || result["body"] || "",
              }
            else
              JSON.parse(raw)
            end

          meta = payload["_meta"] || payload["frontmatter"] || {}
          body = payload["body"] || ""
          if_etag = payload["if_etag"]
          ctx = Textus::Composition.context(store, role: role)
          emit(Textus::Composition.writes_put(ctx).call(key, meta: meta, body: body, if_etag: if_etag))
        end
      end
    end
  end
end
