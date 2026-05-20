require "json"
require "csv"
require "yaml"
require "rexml/document"

module Textus
  module BuiltinActions
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def self.register_all
      Textus.action(:json) do |config:, store:, args:|
        _ = store
        _ = args
        data = JSON.parse(config["bytes"].to_s)
        { frontmatter: {}, body: YAML.dump(data) }
      end

      Textus.action(:csv) do |config:, store:, args:|
        _ = store
        _ = args
        rows = CSV.parse(config["bytes"].to_s, headers: true).map(&:to_h)
        { frontmatter: {}, body: YAML.dump(rows) }
      end

      Textus.action(:"markdown-links") do |config:, store:, args:|
        _ = store
        _ = args
        links = config["bytes"].to_s.scan(%r{\[([^\]]+)\]\((https?://[^)\s]+)\)}).map do |text, href|
          { "text" => text, "href" => href }
        end
        { frontmatter: {}, body: YAML.dump(links) }
      end

      Textus.action(:"ical-events") do |config:, store:, args:|
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
        { frontmatter: {}, body: YAML.dump(events) }
      end

      Textus.action(:rss) do |config:, store:, args:|
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
        { frontmatter: {}, body: YAML.dump(items) }
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
  end
end
