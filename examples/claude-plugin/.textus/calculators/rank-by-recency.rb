Textus::Calculators.register("rank-by-recency", ->(rows) {
  rows.sort_by { |r| r["updated_at"].to_s }.reverse
})
