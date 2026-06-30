# rubocop:disable Metrics/BlockLength
Textus.workflow "decisions-log" do
  match "artifacts.decisions.log"

  # Keep the body concise for RuboCop's block-length rule by delegating
  # work to small lambdas.
  step :build do |_, ctx|
    require "digest"

    normalize = ->(s) { s.to_s.gsub(/\[([^\]]+)\]\([^)]+\)/, '\1').gsub(/\s+/, " ").strip }

    keys = ctx.container.manifest.resolver
              .enumerate(prefix: "knowledge.decisions", include_keyless: true)
              .map { |row| row[:key] }

    reader = ctx.container.reader

    # Pull the ADRs in a separate helper to keep this block short for RuboCop
    build_adrs = lambda do
      keys.filter_map do |k|
        env = begin
          reader.read(k)
        rescue StandardError
          nil
        end
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
    end

    adrs = build_adrs.call

    # Produce a deterministic _meta.uid derived from the content so repeated
    # runs produce byte-for-byte identical generated artifacts. JSON
    # serialization can vary across Ruby/JSON versions and platforms, which
    # caused CI drift. Build a canonical ASCII string from each ADR's stable
    # fields and hash that instead to ensure cross-platform determinism.
    canonical = adrs.map do |a|
      [a["number"], a["title"], a["date"], a["status"], a["slug"]].join("\u001F")
    end.join("\n")

    uid = Digest::SHA1.hexdigest(canonical)[0, 16]

    { "_meta" => { "uid" => uid }, "content" => { "adrs" => adrs } }
  end

  publish
end
# rubocop:enable Metrics/BlockLength
