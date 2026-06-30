Textus.workflow "decisions-log" do
  match "artifacts.decisions.log"

  step :build do |_, ctx|
    normalize = ->(s) { s.to_s.gsub(/\[([^\]]+)\]\([^)]+\)/, '\1').gsub(/\s+/, " ").strip }

    envelopes = ctx.container.read_family("knowledge.decisions", include_keyless: true)

    build_adrs = lambda do
      envelopes.filter_map do |env|
        slug = env.key.split(".").last
        next unless (m = slug.match(/\A(\d{4})-(.+)\z/))

        text        = env.body.to_s
        title_match = text.match(/^#\s*(?:ADR\s+)?\d[\d.]*\s*[—-]\s*(.+)$/)
        title       = title_match ? title_match[1].strip : slug.sub(/\A\d+-/, "").gsub("-", " ")

        {
          "number" => m[1],
          "title" => normalize.call(title),
          "date" => text[/^\*\*Date:\*\*\s*(.+)$/, 1]&.strip,
          "status" => normalize.call(text[/^\*\*Status:\*\*\s*(.+)$/, 1]),
          "slug" => slug,
        }
      end.sort_by { |a| a["number"].to_i }.reverse
    end

    { "content" => { "adrs" => build_adrs.call } }
  end

  publish
end
