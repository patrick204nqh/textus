require "csv"
Textus::Parsers.register("csv", lambda { |content|
  rows = CSV.parse(content, headers: true)
  rows.map(&:to_h)
})
