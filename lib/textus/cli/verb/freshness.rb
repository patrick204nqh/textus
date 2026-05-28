module Textus
  class CLI
    class Verb
      class Freshness < Verb
        command_name "freshness"

        option :prefix, "--prefix=KEY"
        option :zone, "--zone=Z"

        def call(store)
          rows = session_for(store).freshness(prefix: prefix, zone: zone)
          emit({ "verb" => "freshness", "rows" => rows })
        end
      end
    end
  end
end
