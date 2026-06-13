module Textus
  module Doctor
    class Check
      # For every entry with a fetch handler, look up its handler_permit policy
      # (if any) and verify the declared handler is permitted. Emits a failure
      # when the handler is rejected by policy.
      class HandlerPermit < Check
        def call
          out = []
          manifest.data.entries.each do |mentry|
            next unless mentry.intake?

            handler = mentry.handler

            permit = manifest.rules.for(mentry.key).handler_permit
            next if permit.nil?
            next if permit.permits?(handler)

            out << {
              "code" => "policy.handler_not_permitted",
              "level" => "error",
              "subject" => mentry.key,
              "message" => "entry '#{mentry.key}' declares source.handler='#{handler}' but " \
                           "handler_permit allows only: #{permit.handlers.join(", ")}",
              "fix" => "change handler to one of [#{permit.handlers.join(", ")}] or " \
                       "extend handler_permit in .textus/manifest.yaml",
            }
          end
          out
        end
      end
    end
  end
end
