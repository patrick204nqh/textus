module Textus
  class CLI
    class Verb
      class Published < Verb
        def call(store)
          emit({ "published" => operations_for(store).reads.published.call })
        end
      end
    end
  end
end
