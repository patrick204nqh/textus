require "csv"
Textus::Parsers.register("csv", ->(content) {
  rows = CSV.parse(content, headers: true)
  rows.map { |r| r.to_h }
})
