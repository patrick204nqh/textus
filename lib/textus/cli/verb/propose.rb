module Textus
  class CLI
    class Verb
      # Queue a proposal. Mirrors the MCP `propose` tool: resolves the
      # manifest's propose_zone and prefixes the key, so the author does not
      # need to know the queue zone's name. ADR 0036.
      class Propose < Runner::Base
        self.spec = Textus::Write::Propose.contract
        command_name "propose"

        option :as_flag, "--as=ROLE"
        option :use_stdin, "--stdin"

        def invoke(store)
          rel = positional.shift or raise UsageError.new("propose requires a key")
          raise UsageError.new("propose requires --stdin") unless use_stdin

          payload = JSON.parse(@stdin.read)
          env = store.as(resolved_role(store)).propose(
            rel,
            meta: payload["_meta"] || {},
            body: payload["body"] || "",
          )
          emit(env.to_h_for_wire)
        end
      end
    end
  end
end
