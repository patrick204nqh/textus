Textus.hook(:reduce, :"rank-by-recency") do |store:, rows:, config:|
  _ = store
  _ = config
  rows.sort_by { |r| r["updated_at"].to_s }.reverse
end
