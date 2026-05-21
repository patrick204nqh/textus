module Textus
  class CLI
    class Put < Verb
      option :as_flag, "--as=ROLE"
      option :use_stdin, "--stdin"
      option :action_name, "--action=NAME"

      def call(store) # rubocop:disable Metrics/AbcSize
        key = positional.shift or raise UsageError.new("put requires a key")
        raise UsageError.new("put requires --stdin in v1") unless use_stdin

        role = Role.resolve(flag: as_flag, env: ENV, root: store.root)

        raw = @stdin.read
        payload =
          if action_name
            callable = store.registry.action(action_name)
            result =
              begin
                Timeout.timeout(Textus::Refresh::ACTION_TIMEOUT_SECONDS) do
                  callable.call(config: { "bytes" => raw }, store: Textus::StoreView.new(store), args: {})
                end
              rescue Timeout::Error
                raise UsageError.new(
                  "action '#{action_name}' exceeded #{Textus::Refresh::ACTION_TIMEOUT_SECONDS}s timeout",
                )
              end
            basename = key.split(".").last
            {
              "_meta" => {
                "name" => basename,
                "last_refreshed_at" => Time.now.utc.iso8601,
                "actioned_with" => action_name,
              }.merge(result[:_meta] || result["_meta"] || result[:frontmatter] || result["frontmatter"] || {}),
              "body" => result[:body] || result["body"] || "",
            }
          else
            JSON.parse(raw)
          end

        meta = payload["_meta"] || payload["frontmatter"] || {}
        body = payload["body"] || ""
        if_etag = payload["if_etag"]
        emit(store.put(key, meta: meta, body: body, if_etag: if_etag, as: role))
      end
    end
  end
end
