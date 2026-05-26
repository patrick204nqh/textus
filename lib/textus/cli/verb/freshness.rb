module Textus
  class CLI
    class Verb
      class Freshness < Verb
        command_name "freshness"

        option :prefix, "--prefix=KEY"
        option :zone, "--zone=Z"

        def call(store)
          rows = operations_for(store).reads.freshness.call(prefix: prefix, zone: zone)
          emit({ "verb" => "freshness", "rows" => rows })
        end
      end
    end
  end
end
