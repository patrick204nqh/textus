# Wraps the canon.plugin row into the Claude Code plugin.json envelope.
# Strips internal `_key` and `generated` metadata before emitting.
Textus.reducer(:"plugin-envelope") do |rows:, config:|
  _ = config
  row = rows.first || {}
  body = row.reject { |k, _| k.start_with?("_") || k == "generated" }
  { "$schema" => "https://code.claude.com/schemas/plugin.json" }.merge(body)
end
