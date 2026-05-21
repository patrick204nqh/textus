module Textus
  class CLI
    class Build < Verb
      option :prefix, "--prefix=K"

      def call(store)
        emit(Textus::Builder.new(store).build(prefix: prefix))
      end
    end
  end
end
