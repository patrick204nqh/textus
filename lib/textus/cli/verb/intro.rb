module Textus
  class CLI
    class Verb
      class Intro < Verb
        def call(store)
          emit(Textus::Intro.run(store))
        end
      end
    end
  end
end
