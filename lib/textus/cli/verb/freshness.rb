module Textus
  class CLI
    class Verb
      class Freshness < Verb
        option :prefix, "--prefix=KEY"
        option :zone, "--zone=Z"

        def call(store)
          ctx = context_for(store)
          rows = Textus::Composition.freshness(ctx).call(prefix: prefix, zone: zone)
          emit({ "verb" => "freshness", "rows" => rows })
        end
      end
    end
  end
end
