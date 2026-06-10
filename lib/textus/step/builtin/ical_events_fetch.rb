# frozen_string_literal: true

require "yaml"

module Textus
  module Step
    module Builtin
      class IcalEventsFetch < Step::Fetch
        step_name "ical-events"
        def call(config:, args:, **)
          _ = args
          events_list = []
          current = nil
          config["bytes"].to_s.each_line do |line|
            line = line.strip
            case line
            when "BEGIN:VEVENT" then current = {}
            when "END:VEVENT"
              events_list << current if current
              current = nil
            when /\A(SUMMARY|DTSTART|DTEND|UID|LOCATION|DESCRIPTION):(.*)\z/
              current[Regexp.last_match(1).downcase] = Regexp.last_match(2) if current
            end
          end
          { _meta: {}, body: YAML.dump(events_list) }
        end
      end
    end
  end
end
