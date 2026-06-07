# Reshapes projected knowledge.decisions rows into ADR-index template data
# (ADR 0097). Store-reactive via rdeps. Parses the markdown headers the
# historical ADRs carry instead of frontmatter (they are schema: null).
#
# Expected projection spec:
#   pluck: [body, _key]
#   transform: adr_index_reducer
#
# Number is derived from the entry key/filename (NNNN-slug) — reliable even
# when the heading omits the "ADR" prefix (e.g. 0005-style) or carries a
# malformed version string (0001-style heading bug). Rows whose key does not
# match the NNNN-slug pattern (e.g. the README) are silently excluded.
Textus.hook do |reg| # rubocop:disable Metrics/BlockLength
  reg.on(:transform_rows, :adr_index_reducer) do |rows:, **|
    # Flatten "[label](url)" links to label text (data normalization — ADR 0094:
    # source produces data; no pipe-escaping, that is a render-target concern).
    normalize = lambda do |s|
      s.to_s
       .gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')
       .gsub(/\s+/, " ")
       .strip
    end

    adrs = rows.filter_map do |row|
      key = row["_key"].to_s
      # Extract the NNNN-slug segment from a key like knowledge.decisions.NNNN-slug
      slug_segment = key.split(".").last
      next nil unless (num_match = slug_segment.match(/\A(\d{4})-(.+)\z/))

      number = num_match[1]
      slug = slug_segment # e.g. "0005-store-facade-final-removal"

      text = row["body"].to_s
      # Accept either "# ADR NNNN — Title" or "# NNNN — Title" (0005-style)
      title_match = text.match(/^#\s*(?:ADR\s+)?\d[\d.]*\s*[—-]\s*(.+)$/)
      title = title_match ? title_match[1].strip : slug.sub(/\A\d+-/, "").gsub("-", " ")

      {
        "number" => number,
        "title" => normalize.call(title),
        "date" => text[/^\*\*Date:\*\*\s*(.+)$/, 1]&.strip,
        "status" => normalize.call(text[/^\*\*Status:\*\*\s*(.+)$/, 1]),
        "slug" => slug,
      }
    end.sort_by { |a| a["number"].to_i }.reverse

    { "adrs" => adrs }
  end
end
