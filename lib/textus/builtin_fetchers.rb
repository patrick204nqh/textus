require "json"
require "csv"
require "yaml"
require "rexml/document"

module Textus
  module BuiltinFetchers
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def self.register_all
      Textus.fetcher(:json) do |config:, store:|
        _ = store
        data = JSON.parse(config["bytes"].to_s)
        { frontmatter: {}, body: YAML.dump(data) }
      end

      Textus.fetcher(:csv) do |config:, store:|
        _ = store
        rows = CSV.parse(config["bytes"].to_s, headers: true).map(&:to_h)
        { frontmatter: {}, body: YAML.dump(rows) }
      end

      Textus.fetcher(:"markdown-links") do |config:, store:|
        _ = store
        links = config["bytes"].to_s.scan(%r{\[([^\]]+)\]\((https?://[^)\s]+)\)}).map do |text, href|
          { "text" => text, "href" => href }
        end
        { frontmatter: {}, body: YAML.dump(links) }
      end

      Textus.fetcher(:"ical-events") do |config:, store:|
        _ = store
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

      Textus.fetcher(:rss) do |config:, store:|
        _ = store
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
