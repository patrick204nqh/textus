module Textus
  class CLI
    class Verb
      class Published < Verb
        def call(store)
          emit({ "published" => store.published })
        end
      end
    end
  end
end
