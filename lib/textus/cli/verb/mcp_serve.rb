module Textus
  class CLI
    class Verb
      # Launches the MCP stdio server in the current process. Blocks on
      # stdin; never returns until stdin closes.
      class MCPServe < Verb
        command_name "serve"
        parent_group Group::MCP

        def call(store)
          Textus::MCP::Server.new(store: store, stdin: @stdin, stdout: @stdout).run
          0
        end
      end
    end
  end
end
