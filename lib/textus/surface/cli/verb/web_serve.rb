module Textus
  module Surface
    class CLI
      class Verb
        class WebServe < Verb
          command_name "serve"
          parent_group Group::Web
          option :as_flag, "--as=ROLE"
          option :port, "--port=N"

          def call(store)
            role = resolved_role(store, default: Textus::Value::Role::AGENT)
            Textus::Surface::Web.set :textus_session, store.with_role(role)
            Textus::Surface::Web.set :port, (port || 9292).to_i
            Textus::Surface::Web.run!
            0
          end
        end
      end
    end
  end
end
