# frozen_string_literal: true

module Textus
  module Action
    class Propose < Base
      extend Textus::Contract::DSL

      verb :propose
      summary "Write a proposal to the role's propose_lane. Auto-prefixes the key."
      surfaces :cli, :mcp
      cli_stdin :json
      arg :key, String, required: true, positional: true,
                        description: "key relative to propose_lane, e.g. 'decisions.feature-x'"
      arg :meta, Hash, required: false, wire_name: :_meta,
                       description: "frontmatter; reads back as `_meta` from `get`. Include a 'proposal:' block naming the target_key"
      arg :body, String,
          description: "markdown/text payload for markdown-format entries; omit (use `content`) for json/yaml entries. Do not send both"
      arg :content, Hash,
          description: "structured payload for json/yaml-format entries; omit (use `body`) for markdown entries. Do not send both"
      view { |env, _i| env.to_h_for_wire }

      def self.call(container:, call:, key:, meta: nil, body: nil, content: nil)
        zone = container.manifest.policy.propose_lane_for(call.role)
        unless zone
          raise Textus::Error.new(
            "propose_forbidden",
            "role '#{call.role}' has no writable propose_lane",
            details: { "role" => call.role },
            hint: "the manifest must define a queue zone and '#{call.role}' must hold the 'propose' capability",
          )
        end

        mentry = container.manifest.resolver.resolve("#{zone}.#{key}").entry
        container.compositor.write(
          "#{zone}.#{key}",
          mentry: mentry,
          payload: Textus::Store::Envelope::Writer::Payload.new(
            meta: meta || {},
            body: body,
            content: content,
          ),
          call: call,
        )
      end
    end
  end
end
