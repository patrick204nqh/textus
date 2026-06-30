# rubocop:disable Metrics/BlockLength
Textus.workflow "docs-index" do
  match "artifacts.docs.index"

  step :scan do |_, ctx| # rubocop:disable Metrics/BlockLength
    resolver = ctx.container.manifest.resolver
    ctx.call

    extract = lambda { |entry|
      env = ctx.container.reader.read(entry[:key])
      body = env.body.to_s
      body = body.sub(/\A---\s*\n.*?^---\s*\n/m, "")
      title = body.lines.first&.sub(/\A#\s+/, "")&.strip || entry[:key]
      desc = ""
      body.each_line do |line|
        if line.match?(/\A> \*\*./)
          desc = line.sub(/\A> \*\*[^*]+\*\*\s*/, "").strip
          break
        end
      end
      suffix = entry[:key].sub(/\Aknowledge\./, "").tr(".", "/")
      { "title" => title, "desc" => desc, "link" => "#{suffix}.md" }
    }

    how_to = resolver.enumerate(prefix: "knowledge.how-to", include_keyless: true)
                     .reject { |r| r[:key] == "knowledge.how-to" }
                     .uniq { |r| r[:key] }
                     .sort_by { |r| r[:key] }
                     .map(&extract)

    reference = resolver.enumerate(prefix: "knowledge.reference", include_keyless: true)
                        .reject { |r| r[:key] == "knowledge.reference" }
                        .uniq { |r| r[:key] }
                        .sort_by { |r| r[:key] }
                        .map(&extract)

    explanation = resolver.enumerate(prefix: "knowledge.explanation", include_keyless: true)
                          .reject { |r| r[:key] == "knowledge.explanation" }
                          .uniq { |r| r[:key] }
                          .sort_by { |r| r[:key] }
                          .map(&extract)

    cookbook = resolver.enumerate(prefix: "knowledge.cookbook", include_keyless: true)
                       .reject { |r| r[:key] == "knowledge.cookbook" }
                       .uniq { |r| r[:key] }
                       .sort_by { |r| r[:key] }
                       .map(&extract)

    { "content" => {
      "how_to" => how_to,
      "reference" => reference,
      "explanation" => explanation,
      "cookbook" => cookbook,
    } }
  end

  publish
end
# rubocop:enable Metrics/BlockLength
