module Textus
  class CLI
    class Build < Verb
      option :prefix, "--prefix=K"

      def call(store)
        res = Textus::Builder.new(store).build(prefix: prefix)
        @stdout.puts(JSON.generate(res))
        0
      end
    end
  end
end
