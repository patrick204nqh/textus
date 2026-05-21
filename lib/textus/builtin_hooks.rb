require "json"
require "csv"
require "yaml"
require "rexml/document"

module Textus
  module BuiltinHooks
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def self.register_all
      Textus.hook(:fetch, :json) do |store:, config:, args:|
        _ = store
        _ = args
        data = JSON.parse(config["bytes"].to_s)
        { _meta: {}, body: YAML.dump(data) }
      end

      Textus.hook(:fetch, :csv) do |store:, config:, args:|
        _ = store
        _ = args
        rows = CSV.parse(config["bytes"].to_s, headers: true).map(&:to_h)
        { _meta: {}, body: YAML.dump(rows) }
      end

      Textus.hook(:fetch, :"markdown-links") do |store:, config:, args:|
        _ = store
        _ = args
        links = config["bytes"].to_s.scan(%r{\[([^\]]+)\]\((https?://[^)\s]+)\)}).map do |text, href|
          { "text" => text, "href" => href }
        end
        { _meta: {}, body: YAML.dump(links) }
      end

      Textus.hook(:fetch, :"ical-events") do |store:, config:, args:|
        _ = store
        _ = args
        events = []
        current = nil
        config["bytes"].to_s.each_line do |line|
          line = line.strip
          case line
          when "BEGIN:VEVENT" then current = {}
          when "END:VEVENT"
            events << current if current
            current = nil
          when /\A(SUMMARY|DTSTART|DTEND|UID|LOCATION|DESCRIPTION):(.*)\z/
            current[Regexp.last_match(1).downcase] = Regexp.last_match(2) if current
          end
        end
        { _meta: {}, body: YAML.dump(events) }
      end

      Textus.hook(:fetch, :rss) do |store:, config:, args:|
        _ = store
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
