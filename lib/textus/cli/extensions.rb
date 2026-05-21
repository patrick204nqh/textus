module Textus
  class CLI
    class Extensions < Verb
      option :kind, "--kind=K"

      def call(store) # rubocop:disable Metrics/AbcSize
        subcommand = positional.shift
        raise UsageError.new("extensions requires 'list'") unless subcommand == "list"

        rows = []
        rows += store.registry.action_names.map { |n| { "kind" => "action", "name" => n.to_s } }
        rows += store.registry.doctor_check_names.map { |n| { "kind" => "doctor_check", "name" => n.to_s } }
        rows += store.registry.reducer_names.map { |n| { "kind" => "reducer", "name" => n.to_s } }
        store.registry.hook_events.each do |evt|
          store.registry.hooks(evt).each do |h|
            rows << { "kind" => "hook", "event" => evt.to_s, "name" => h[:name].to_s }
          end
        end
        store.manifest.entries.each do |e|
          e.events.each do |evt, defs|
            Array(defs).each do |defn|
              next unless defn["exec"]

              rows << {
                "kind" => "hook", "event" => evt.to_s, "exec" => defn["exec"],
                "key" => e.key, "as" => defn["as"] || "script"
              }
            end
          end
        end
        rows.select! { |r| r["kind"] == kind } if kind

        emit({ "protocol" => PROTOCOL, "extensions" => rows })
      end
    end
  end
end
