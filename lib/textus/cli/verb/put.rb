module Textus
  class CLI
    class Verb
      class Put < Runner::Base
        self.spec = Textus::Write::Put.contract

        option :as_flag, "--as=ROLE"
        option :use_stdin, "--stdin"
        option :fetch_name, "--fetch=NAME"

        def invoke(store)
          key = positional.shift or raise UsageError.new("put requires a key")
          raise UsageError.new("put requires --stdin in v1") unless use_stdin

          role = resolved_role(store)

          raw = @stdin.read
          payload =
            if fetch_name
              result = Textus::Write::IntakeFetch.invoke(
                caps: store.container, handler: fetch_name,
                config: { "bytes" => raw }, args: {}, label: "fetch"
              )
              basename = key.split(".").last
              {
                "_meta" => {
                  "name" => basename,
                  "last_fetched_at" => Time.now.utc.iso8601,
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
          result = store.as(role).put(key, meta: meta, body: body, if_etag: if_etag)
          emit(result.to_h_for_wire)
        end
      end
    end
  end
end
