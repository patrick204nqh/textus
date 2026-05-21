Textus.reduce(:rank_by_recency) do |rows:, **|
  rows.sort_by { |r| r["updated_at"].to_s }.reverse
end
