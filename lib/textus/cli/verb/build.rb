module Textus
  class CLI
    class Verb
      class Build < Verb
        command_name "build"

        option :prefix, "--prefix=K"

        def call(store)
          Textus::Infra::BuildLock.with(root: store.root) do
            ops = Textus::Operations.for(store, role: "builder")
            build_res   = ops.build(prefix: prefix)
            publish_res = ops.publish(prefix: prefix)
            emit({ "protocol" => Textus::PROTOCOL,
                   "built" => build_res["built"],
                   "published_leaves" => publish_res["published_leaves"] })
          end
        end
      end
    end
  end
end
