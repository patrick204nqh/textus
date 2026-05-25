# Wraps the identity.plugin row into the Claude Code plugin.json envelope.
# Strips internal `_key` and `generated` metadata before emitting.
Textus.on(:transform_rows, :plugin_envelope) do |rows:, **|
  row = rows.first || {}
  body = row.reject { |k, _| k.start_with?("_") || k == "generated" }
  { "$schema" => "https://code.claude.com/schemas/plugin.json" }.merge(body)
end
