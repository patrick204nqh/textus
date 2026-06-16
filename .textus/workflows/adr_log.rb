Textus.workflow "adr_log" do
  match "artifacts.derived.adr-log"

  step :derive do |data, ctx|
    normalize = ->(s) { s.to_s.gsub(/\[([^\]]+)\]\([^)]+\)/, '\1').gsub(/\s+/, " ").strip }

    decision_keys = Textus::Action::List.new(prefix: "knowledge.decisions", lane: nil,
                                             role: ctx.call.role)
                      .call(container: ctx.container, call: ctx.call)
                      .fetch("entries", []).map { |e| e["key"] }

    adrs = decision_keys.filter_map do |k|
      env  = Textus::Action::Get.new(key: k).call(container: ctx.container, call: ctx.call)
      next nil unless env

      slug = k.split(".").last
      next nil unless (m = slug.match(/\A(\d{4})-(.+)\z/))

      text         = env.body.to_s
      title_match  = text.match(/^#\s*(?:ADR\s+)?\d[\d.]*\s*[—-]\s*(.+)$/)
      title        = title_match ? title_match[1].strip : slug.sub(/\A\d+-/, "").gsub("-", " ")

      {
        "number" => m[1],
        "title"  => normalize.call(title),
        "date"   => text[/^\*\*Date:\*\*\s*(.+)$/, 1]&.strip,
        "status" => normalize.call(text[/^\*\*Status:\*\*\s*(.+)$/, 1]),
        "slug"   => slug,
      }
    end.sort_by { |a| a["number"].to_i }.reverse

    { "adrs" => adrs }
  end

  publish
end
