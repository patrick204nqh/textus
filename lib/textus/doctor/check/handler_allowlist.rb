module Textus
  module Doctor
    class Check
      # For every entry with an `intake.handler`, look up its handler_allowlist
      # policy (if any) and verify the declared handler is allowed. Emits a
      # failure when the handler is rejected by policy.
      class HandlerAllowlist < Check
        def call
          out = []
          store.manifest.entries.each do |mentry|
            handler = mentry.intake_handler
            next if handler.nil?

            allow = store.manifest.policies_for(mentry.key).handler_allowlist
            next if allow.nil?
            next if allow.allows?(handler)

            out << {
              "code" => "policy.handler_not_allowed",
              "level" => "error",
              "subject" => mentry.key,
              "message" => "entry '#{mentry.key}' declares intake.handler='#{handler}' but the " \
                           "handler_allowlist policy permits only: #{allow.handlers.join(", ")}",
              "fix" => "either change intake.handler to one of [#{allow.handlers.join(", ")}], " \
                       "or extend the handler_allowlist policy in .textus/manifest.yaml",
            }
          end
          out
        end
      end
    end
  end
end
