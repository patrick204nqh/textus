module Textus
  class Manifest
    class Entry
      module Validators
        module Events
          def self.call(entry, policy: nil) # rubocop:disable Lint/UnusedMethodArgument
            pubsub_events = Textus::Hooks::EventBus::EVENTS.keys
            events = entry.events
            events.each_key do |evt|
              next if pubsub_events.include?(evt.to_sym)

              raise UsageError.new(
                "entry '#{entry.key}': unknown event '#{evt}' in events: block. " \
                "Known events: #{pubsub_events.join(", ")}.",
              )
            end
          end
        end
      end
    end
  end
end
