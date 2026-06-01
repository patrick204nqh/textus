module Textus
  class CLI
    class Verb
      class Hooks < Verb
        command_name "list"
        parent_group Group::Hook

        option :event_filter, "--event=E"

        def call(store) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
          subcommand = positional.first
          if subcommand
            raise UsageError.new("hook requires 'list'") unless subcommand == "list"

            positional.shift
          end

          rows = []
          Textus::Hooks::Catalog::RPC.each_key do |event|
            store.rpc.names(event).each do |name|
              rows << { "event" => event.to_s, "mode" => "rpc", "name" => name.to_s }
            end
          end
          Textus::Hooks::Catalog::PUBSUB.each_key do |event|
            store.events.pubsub_handlers(event).each do |h|
              row = { "event" => event.to_s, "mode" => "pubsub", "name" => h[:name].to_s }
              row["keys"] = Array(h[:keys]) if h[:keys]
              rows << row
            end
          end
          store.manifest.data.entries.each do |e|
            (e.respond_to?(:events) ? e.events : {}).each do |evt, defs|
              Array(defs).each do |defn|
                next unless defn["exec"]

                rows << {
                  "event" => evt.to_s, "mode" => "manifest", "exec" => defn["exec"],
                  "key" => e.key, "as" => defn["as"] || Textus::Role::AUTOMATION
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
end
