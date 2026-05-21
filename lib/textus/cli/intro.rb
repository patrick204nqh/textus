module Textus
  class CLI
    class IntroVerb < Verb
      def call(store)
        emit(Textus::Intro.run(store))
      end
    end
  end
end
