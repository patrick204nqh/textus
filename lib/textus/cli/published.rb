module Textus
  class CLI
    class Published < Verb
      def call(store)
        emit({ "protocol" => PROTOCOL, "published" => store.published })
      end
    end
  end
end
