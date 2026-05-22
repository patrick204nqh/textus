module Textus
  class CLI
    class Verb
      class Freshness < Verb
        option :prefix, "--prefix=KEY"
        option :zone, "--zone=Z"

        def call(store)
          role = Role.resolve(flag: nil, env: ENV, root: store.root)
          ctx = Textus::Composition.context(store, role: role)
          rows = Textus::Composition.freshness(ctx).call(prefix: prefix, zone: zone)
          emit({ "verb" => "freshness", "rows" => rows })
        end
      end
    end
  end
end
