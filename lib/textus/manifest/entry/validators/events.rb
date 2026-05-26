module Textus
  class Manifest
    class Entry
      module Validators
        module Events
          def self.call(entry)
            pubsub_events = Textus::Hooks::Registry::EVENTS.select { |_, s| s[:mode] == :pubsub }.keys
            entry.events.each_key do |evt|
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
