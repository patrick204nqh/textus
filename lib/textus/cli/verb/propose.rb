module Textus
  class CLI
    class Verb
      # Queue a proposal. Mirrors the MCP `propose` tool: resolves the
      # manifest's propose_zone and prefixes the key, so the author does not
      # need to know the queue zone's name. ADR 0036.
      class Propose < Verb
        command_name "propose"

        option :as_flag, "--as=ROLE"
        option :use_stdin, "--stdin"

        def call(store)
          rel = positional.shift or raise UsageError.new("propose requires a key")
          raise UsageError.new("propose requires --stdin") unless use_stdin

          role = resolved_role(store)
          zone = store.manifest.policy.propose_zone_for(store.manifest.policy.proposer_role)
          raise UsageError.new("no propose_zone is defined in this manifest") unless zone

          payload = JSON.parse(@stdin.read)
          result = store.as(role).put(
            "#{zone}.#{rel}",
            meta: payload["_meta"] || {},
            body: payload["body"] || "",
          )
          emit(result.to_h_for_wire)
        end
      end
    end
  end
end
