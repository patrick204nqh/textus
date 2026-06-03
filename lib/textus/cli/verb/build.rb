module Textus
  class CLI
    class Verb
      class Build < Verb
        command_name "build"

        option :prefix, "--prefix=K"

        def call(store)
          role = store.manifest.policy.actor_for("build") or
            raise UsageError.new(
              "no role holds the 'build' capability",
              hint: "declare a role with `can: [build]` in .textus/manifest.yaml",
            )
          Textus::Ports::BuildLock.with(root: store.root) do
            ops = store.as(role)
            result = ops.build(prefix: prefix)
            emit(result)
          end
        end
      end
    end
  end
end
