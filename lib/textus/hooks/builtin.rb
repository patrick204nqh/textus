require "json"
require "csv"
require "yaml"
require "rexml/document"

module Textus
  module Hooks
    module Builtin
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def self.register_all(events:, rpc:) # rubocop:disable Lint/UnusedMethodArgument
        rpc.register(:resolve_intake, :json) do |caps:, config:, args:|
          _ = caps
          _ = args
          data = JSON.parse(config["bytes"].to_s)
          { _meta: {}, body: YAML.dump(data) }
        end

        rpc.register(:resolve_intake, :csv) do |caps:, config:, args:|
          _ = caps
          _ = args
          rows = CSV.parse(config["bytes"].to_s, headers: true).map(&:to_h)
          { _meta: {}, body: YAML.dump(rows) }
        end

        rpc.register(:resolve_intake, :"markdown-links") do |caps:, config:, args:|
          _ = caps
          _ = args
          links = config["bytes"].to_s.scan(%r{\[([^\]]+)\]\((https?://[^)\s]+)\)}).map do |text, href|
            { "text" => text, "href" => href }
          end
          { _meta: {}, body: YAML.dump(links) }
        end

        rpc.register(:resolve_intake, :"ical-events") do |caps:, config:, args:|
          _ = caps
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

        rpc.register(:resolve_intake, :rss) do |caps:, config:, args:|
          _ = caps
          _ = args
          doc = REXML::Document.new(config["bytes"].to_s)
          items = doc.elements.to_a("//item").map do |item|
            {
              "title" => item.elements["title"]&.text,
              "link" => item.elements["link"]&.text,
              "pubDate" => item.elements["pubDate"]&.text,
            }
          end
          { _meta: {}, body: YAML.dump(items) }
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    end
  end
end
