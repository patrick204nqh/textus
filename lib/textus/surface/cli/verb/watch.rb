module Textus
  module Surface
    class CLI
      class Verb
        class Watch < Verb
          command_name "watch"
          option :as_flag, "--as=ROLE"
          option :poll, "--poll=SECONDS"

          def call(store)
            watcher = Textus::Surface::Watcher.new(container: store.container)
            watcher.run(poll: poll&.to_f)
            0
          end
        end
      end
    end
  end
end
