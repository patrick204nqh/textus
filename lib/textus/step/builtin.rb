# frozen_string_literal: true

module Textus
  module Step
    # Registers the framework-provided fetch steps (json/csv/markdown-links/
    # ical-events/rss) into a registry at Store construction. The successor to
    # Hooks::Builtin.register_all.
    module Builtin
      STEPS = [
        JsonFetch, CsvFetch, MarkdownLinksFetch, IcalEventsFetch, RssFetch
      ].freeze

      def self.register_all(registry)
        STEPS.each do |klass|
          step = klass.new
          step.name = klass.step_name
          registry.register(step)
        end
      end
    end
  end
end
