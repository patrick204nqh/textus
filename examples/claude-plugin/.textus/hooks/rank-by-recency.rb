Textus.reducer(:"rank-by-recency") do |rows:, config:|
  rows.sort_by { |r| r["updated_at"].to_s }.reverse
end
