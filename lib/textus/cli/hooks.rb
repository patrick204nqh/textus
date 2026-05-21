module Textus
  class CLI
    class Hooks < Verb
      option :event_filter, "--event=E"

      def call(store) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
        subcommand = positional.first
        if subcommand
          raise UsageError.new("hook requires 'list'") unless subcommand == "list"

          positional.shift
        end

        rows = []
        Textus::Hooks::Registry::EVENTS.each do |event, spec|
          mode = spec[:mode].to_s
          case spec[:mode]
          when :rpc
            store.registry.rpc_names(event).each do |name|
              rows << { "event" => event.to_s, "mode" => mode, "name" => name.to_s }
            end
          when :pubsub
            store.registry.pubsub_handlers(event).each do |h|
              row = { "event" => event.to_s, "mode" => mode, "name" => h[:name].to_s }
              row["keys"] = Array(h[:keys]) if h[:keys]
              rows << row
            end
          end
        end
        store.manifest.entries.each do |e|
          e.events.each do |evt, defs|
            Array(defs).each do |defn|
              next unless defn["exec"]

              rows << {
                "event" => evt.to_s, "mode" => "manifest", "exec" => defn["exec"],
                "key" => e.key, "as" => defn["as"] || "script"
              }
            end
          end
        end
        rows.select! { |r| r["event"] == event_filter } if event_filter

        emit({ "hooks" => rows })
      end
    end
  end
end
