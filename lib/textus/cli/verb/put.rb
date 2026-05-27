module Textus
  class CLI
    class Verb
      class Put < Verb
        command_name "put"

        option :as_flag, "--as=ROLE"
        option :use_stdin, "--stdin"
        option :fetch_name, "--fetch=NAME"

        def call(store) # rubocop:disable Metrics/AbcSize
          key = positional.shift or raise UsageError.new("put requires a key")
          raise UsageError.new("put requires --stdin in v1") unless use_stdin

          role = resolved_role(store)

          raw = @stdin.read
          payload =
            if fetch_name
              callable = store.registry.rpc_callable(:resolve_intake, fetch_name)
              result =
                begin
                  Timeout.timeout(Textus::Application::Refresh::Worker::FETCH_TIMEOUT_SECONDS) do
                    callable.call(config: { "bytes" => raw },
                                  store: Textus::Application::Context.legacy(store: store, role: role), args: {})
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
                }.merge(result[:_meta] || result["_meta"] || {}),
                "body" => result[:body] || result["body"] || "",
              }
            else
              JSON.parse(raw)
            end

          meta = payload["_meta"] || {}
          body = payload["body"] || ""
          if_etag = payload["if_etag"]
          result = Textus::Operations.for(store, role: role).put(key, meta: meta, body: body, if_etag: if_etag)
          emit(result.to_h_for_wire)
        end
      end
    end
  end
end
