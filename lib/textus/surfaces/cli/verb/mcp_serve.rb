module Textus
  module Surfaces
    class CLI
      class Verb
        # Launches the MCP stdio server in the current process. Blocks on stdin;
        # never returns until stdin closes. The connection acts as the `agent`
        # role by default (ADR 0040): the agent channel proposes, it does not
        # inherit the human's authority. Override per connection with --as, or
        # TEXTUS_ROLE / .textus/role (same chain as every other verb).
        class MCPServe < Verb
          command_name "serve"
          parent_group Group::MCP
          option :as_flag, "--as=ROLE"

          def call(store)
            role = resolved_role(store, default: Textus::Role::AGENT)
            Textus::Surfaces::MCP::Server.new(store: store, stdin: @stdin, stdout: @stdout, role: role).run
            0
          end
        end
      end
    end
  end
end
