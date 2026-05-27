module Textus
  class CLI
    class Verb
      class Build < Verb
        command_name "build"

        option :prefix, "--prefix=K"

        def call(store)
          Textus::Infra::BuildLock.with(root: store.root) do
            role = store.manifest.roles_with_kind(:generator).first || "builder"
            ops = Textus::Operations.for(store, role: role)
            result = ops.publish(prefix: prefix)
            emit(result)
          end
        end
      end
    end
  end
end
