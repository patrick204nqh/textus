require "timeout"

module Textus
  module Parsers
    REGISTRY = {}

    def self.register(name, callable)
      REGISTRY[name] = callable
    end

    def self.parse(name, content)
      callable = REGISTRY[name] or raise UsageError.new("unknown parser: #{name}")
      Timeout.timeout(2) { callable.call(content) }
    rescue Timeout::Error
      raise UsageError.new("parser '#{name}' exceeded 2s timeout")
    end
  end
end

require_relative "parsers/json"
require_relative "parsers/csv"
require_relative "parsers/markdown_links"
require_relative "parsers/ical"
require_relative "parsers/rss"
