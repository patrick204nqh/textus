module Textus
  class CLI
    class Verb
      class Init < Verb
        command_name "init"

        option :with_agent, "--with-agent"

        def self.needs_store? = false

        def call(_store)
          target = File.join(@cwd, ".textus")
          emit(Textus::Init.run(target, with_agent: !!with_agent))
        end
      end
    end
  end
end
