module Textus
  class CLI
    class Verb
      class Blame < Verb
        option :limit, "--limit=N"

        def call(store)
          key = positional.shift or raise UsageError.new("blame requires a key")
          role = Role.resolve(flag: nil, env: ENV, root: store.root)
          ctx = Textus::Composition.context(store, role: role)
          rows = Textus::Composition.blame(ctx).call(key: key, limit: limit&.to_i)
          emit({ "verb" => "blame", "key" => key, "rows" => rows })
        end
      end
    end
  end
end
