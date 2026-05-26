module Textus
  class CLI
    class Verb
      class Intro < Verb
        option :with_examples, "--with-examples"

        def call(store)
          emit(Textus::Intro.run(store, with_examples: !!with_examples))
        end
      end
    end
  end
end
