module Textus
  module Write
    # Queue a proposal: resolve the acting role's propose_zone, prefix the key,
    # and write there via the Put verb. Was inlined in the MCP `propose` tool
    # and the CLI propose verb; promoted to a first-class verb so all three
    # transports share one implementation (ADR 0036, ADR 0039).
    class Propose
      extend Textus::Contract::DSL

      verb     :propose
      summary  "Write a proposal to the role's propose_zone. Auto-prefixes the key."
      surfaces :cli, :ruby, :mcp
      arg :key,     String, required: true, positional: true,
                            description: "key relative to propose_zone, e.g. 'decisions.feature-x'"
      arg :meta,    Hash,   required: true, wire_name: :_meta,
                            description: "frontmatter; reads back as `_meta` from `get`. Include a 'proposal:' block naming the target_key"
      arg :body,    String,
          description: "markdown/text payload for markdown-format entries; omit (use `content`) for json/yaml entries. Do not send both"
      arg :content, Hash,
          description: "structured payload for json/yaml-format entries; omit (use `body`) for markdown entries. Do not send both"
      response { |env| { "uid" => env.uid, "etag" => env.etag, "key" => env.key } }

      def initialize(container:, call:)
        @container = container
        @call      = call
        @manifest  = container.manifest
      end

      # if_etag is intentionally absent: a proposal is always a fresh queue write.
      def call(key, meta: nil, body: nil, content: nil)
        zone = @manifest.policy.propose_zone_for(@call.role)
        unless zone
          raise Textus::Error.new(
            "propose_forbidden",
            "role '#{@call.role}' has no writable propose_zone",
            details: { "role" => @call.role },
            hint: "the manifest must define a queue zone and '#{@call.role}' must hold the 'propose' capability",
          )
        end

        Textus::Dispatcher.invoke(
          :put, container: @container, call: @call,
                args: ["#{zone}.#{key}"],
                kwargs: { meta: meta || {}, body: body, content: content }
        )
      end
    end
  end
end
