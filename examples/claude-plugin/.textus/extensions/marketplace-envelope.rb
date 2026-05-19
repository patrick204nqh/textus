# Wraps a list of skill rows in the marketplace envelope shape.
# Returns a Hash, so the projection's sort/limit/position markers don't apply —
# the builder uses this as the top-level structured payload (with _meta injected first).
Textus.reducer(:"marketplace-envelope") do |rows:, config:|
  _ = config
  {
    "protocol" => "textus/1",
    "skills" => rows,
  }
end
