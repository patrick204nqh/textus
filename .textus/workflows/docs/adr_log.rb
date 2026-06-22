Textus.workflow "adr_log" do
  match "artifacts.docs.adr-log"

  step :build do |_, ctx|
    normalize = ->(s) { s.to_s.gsub(/\[([^\]]+)\]\([^)]+\)/, '\1').gsub(/\s+/, " ").strip }

    keys = ctx.container.manifest.resolver
              .enumerate(prefix: "knowledge.decisions", include_keyless: true)
              .map { |row| row[:key] }

    adrs = keys.filter_map do |k|
      get_spec = Textus::VerbRegistry.for(:get)
      env = Textus::Bus.dispatch(container: ctx.container, spec: get_spec, inputs: { key: k }, role: ctx.call.role) rescue nil
      next unless env

      slug = k.split(".").last
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

    { "content" => { "adrs" => adrs } }
  end

  publish
end
