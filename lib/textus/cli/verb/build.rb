module Textus
  class CLI
    class Verb
      class Build < Verb
        command_name "build"

        option :prefix, "--prefix=K"

        def call(store)
          Textus::Ports::BuildLock.with(root: store.root) do
            role = store.manifest.policy.roles_with_kind(:generator).first || "builder"
            ops = store.as(role)
            result = ops.publish(prefix: prefix)
            emit(result)
          end
        end
      end
    end
  end
end
