module Textus
  module Doctor
    class Check
      class IntakeRegistration < Check
        BUILTIN = %i[json csv markdown-links ical-events rss].freeze

        def call
          declared = collect_declared_handlers
          registered = steps.names(:fetch).to_set

          out = (declared - registered).map do |name|
            {
              "code" => "intake.handler_missing",
              "level" => "error",
              "subject" => name.to_s,
              "message" => "manifest references intake handler '#{name}' but no fetch step for '#{name}' is registered",
              "fix" => "create .textus/steps/fetch/#{name}.rb with `class #{name.to_s.split(/[-_]/).map(&:capitalize).join}Fetch < Textus::Step::Fetch`",
            }
          end

          (registered - declared - BUILTIN.to_set).each do |name|
            out << {
              "code" => "intake.handler_orphan",
              "level" => "warning",
              "subject" => name.to_s,
              "message" => "fetch step '#{name}' is registered but no manifest entry references it",
              "fix" => "remove the unused step, or add an entry with `intake.handler: #{name}`",
            }
          end

          out
        end

        private

        def collect_declared_handlers
          set = Set.new
          manifest.data.entries.each do |mentry|
            set << mentry.handler.to_sym if mentry.intake?
          end
          set
        end
      end
    end
  end
end
