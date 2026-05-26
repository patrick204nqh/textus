module Textus
  class CLI
    class Verb
      class Blame < Verb
        command_name "blame"

        option :limit, "--limit=N"

        def call(store)
          key = positional.shift or raise UsageError.new("blame requires a key")
          rows = operations_for(store).reads.blame.call(key: key, limit: limit&.to_i)
          emit({ "verb" => "blame", "key" => key, "rows" => rows })
        end
      end
    end
  end
end
