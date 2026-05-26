module Textus
  module Doctor
    class Check
      class IntakeRegistration < Check
        BUILTIN = %i[json csv markdown-links ical-events rss].freeze

        def call
          declared = collect_declared_handlers
          registered = store.registry.rpc_names(:resolve_intake).to_set

          out = (declared - registered).map do |name|
            {
              "code" => "intake.handler_missing",
              "level" => "error",
              "subject" => name.to_s,
              "message" => "manifest references intake handler '#{name}' but no resolve_intake hook for '#{name}' is registered",
              "fix" => "create .textus/hooks/#{name}.rb with `Textus.hook { |reg| reg.on(:resolve_intake, :#{name}) { ... } }`",
            }
          end

          (registered - declared - BUILTIN.to_set).each do |name|
            out << {
              "code" => "intake.handler_orphan",
              "level" => "warning",
              "subject" => name.to_s,
              "message" => "resolve_intake hook '#{name}' is registered but no manifest entry references it",
              "fix" => "remove the unused handler, or add an entry with `intake.handler: #{name}`",
            }
          end

          out
        end

        private

        def collect_declared_handlers
          set = Set.new
          store.manifest.entries.each do |mentry|
            set << mentry.intake_handler.to_sym if mentry.intake_handler
          end
          set
        end
      end
    end
  end
end
