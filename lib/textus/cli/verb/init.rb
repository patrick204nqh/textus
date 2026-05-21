module Textus
  class CLI
    class Verb
      class Init < Verb
        def self.needs_store? = false

        def call(_store)
          target = File.join(@cwd, ".textus")
          emit(Textus::Init.run(target))
        end
      end
    end
  end
end
