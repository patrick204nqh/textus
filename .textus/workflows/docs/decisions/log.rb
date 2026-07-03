# rubocop:disable Metrics/BlockLength
Textus.workflow "decisions-log" do
  match "artifacts.decisions.log"

  step :build do |_, ctx|
    normalize = ->(s) { s.to_s.gsub(/\[([^\]]+)\]\([^)]+\)/, '\\1').gsub(/\s+/, " ").strip }
    repo_root = File.dirname(ctx.container.root)

    read_family = lambda do |prefix|
      ctx.container.manifest.resolver.enumerate(prefix: prefix, include_keyless: true)
         .reject { |row| row[:key] == prefix }
         .sort_by { |row| row[:key] }
         .filter_map { |row| ctx.container.reader.read(row[:key]) }
    end

    heading_value = lambda do |text, heading|
      lines = text.lines
      idx = lines.find_index { |line| line.strip == "## #{heading}" }
      next nil unless idx

      lines[(idx + 1)..].to_a.map(&:strip).find { |line| !line.empty? }
    end

    envelopes = read_family.call("knowledge.loop.evidence")

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
          "date" => heading_value.call(text, "Date"),
          "status" => normalize.call(heading_value.call(text, "Status")),
          "slug" => slug,
        }
      end.select { |adr| File.exist?(File.join(repo_root, "docs/architecture/decisions/#{adr["slug"]}.md")) }
         .sort_by { |a| a["number"].to_i }
         .reverse
    end

    { "content" => { "adrs" => build_adrs.call } }
  end
  publish to: "docs/decisions.md", template: "docs/decisions/log.erb"
end
# rubocop:enable Metrics/BlockLength
