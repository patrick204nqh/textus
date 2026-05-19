require "json"
Textus::Parsers.register("json", ->(content) { JSON.parse(content) })
