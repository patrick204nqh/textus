# Reshapes projected knowledge.decisions rows into ADR-index template data
# (ADR 0097). Store-reactive via rdeps. Parses the markdown headers the
# historical ADRs carry instead of frontmatter (they are schema: null).
#
# Expected projection spec:
#   pluck: [body]
#   transform: adr_index_reducer
#
# Rows whose body does not match the `# ADR NNNN — Title` pattern (e.g. the
# README) are silently skipped so the manifest entry can select the whole
# `knowledge.decisions` prefix without an explicit exclusion list.
Textus.hook do |reg|
  reg.on(:transform_rows, :adr_index_reducer) do |rows:, **|
    adrs = rows.filter_map do |row|
      text = row["body"].to_s
      next nil unless (m = text.match(/^#\s*ADR\s+([\d.]+)\s*[—-]\s*(.+)$/))

      {
        "number" => m[1],
        "title" => m[2].strip,
        "date" => text[/^\*\*Date:\*\*\s*(.+)$/, 1]&.strip,
        "status" => text[/^\*\*Status:\*\*\s*(.+)$/, 1]&.strip,
      }
    end.sort_by { |a| a["number"] }.reverse

    { "adrs" => adrs }
  end
end
