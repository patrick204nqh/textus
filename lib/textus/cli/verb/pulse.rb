module Textus
  class CLI
    class Verb
      class Pulse < Verb
        command_name "pulse"

        option :as_flag, "--as=ROLE"
        option :since, "--since=N"

        def call(store)
          role = resolved_role(store)
          ops = store.as(role)

          if since
            emit(ops.pulse(since: since.to_i))
          else
            cursors = Textus::CursorStore.new(root: store.root, role: role)
            result = ops.pulse(since: cursors.read)
            cursors.write(result["cursor"])
            emit(result)
          end
        end
      end
    end
  end
end
