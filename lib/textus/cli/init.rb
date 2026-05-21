module Textus
  class CLI
    class InitVerb < Verb
      def self.needs_store? = false

      def call(_store)
        target = File.join(@cwd, ".textus")
        res = Textus::Init.run(target)
        @stdout.puts(JSON.generate(res))
        0
      end
    end
  end
end
