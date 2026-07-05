# rubocop:disable Metrics/BlockLength
Textus.workflow "changelog" do
  on "artifacts.changelog"
  every "30m"

  TYPE_GROUPS = {
    "feat" => "Features",
    "fix" => "Bug Fixes",
  }.freeze

  step :build do |_, _|
    skip_pattern = /\A(chore: textus drain|Merge )/

    raw = `git log --no-merges --pretty=format:"%D|||%s|||%ad" --date=short 2>/dev/null`.strip
    lines = raw.split("\n").map { |l| l.split("|||") }

    type_order = TYPE_GROUPS.values
    entries = []
    current_tag = "Unreleased"
    current_date = nil
    current_by_type = {}

    flush = lambda do
      groups = type_order.filter_map { |name| [name, current_by_type[name]] if current_by_type[name]&.any? }.to_h
      entries << { "tag" => current_tag, "date" => current_date, "groups" => groups } unless groups.empty?
      current_by_type = {}
    end

    lines.each do |refs, subject, date|
      tag = refs.to_s.scan(/tag: (v[\d.]+)/).flatten.first
      if tag
        flush.call
        current_tag = tag
        current_date = date.to_s.strip
      end
      next unless subject && !subject.to_s.strip.match?(skip_pattern)

      subj = subject.to_s.strip
      type = subj.match(/\A([a-z]+)[(!]/)&.captures&.first
      group = TYPE_GROUPS[type]
      next unless group

      clean = subj.sub(/\A[a-z]+(\([^)]*\))?:[:\s]*/, "")
      (current_by_type[group] ||= []) << { "subject" => clean, "date" => date.to_s.strip }
    end
    flush.call

    { "content" => { "entries" => entries } }
  end
  save to: "artifacts.changelog"
  publish to: "CHANGELOG.md", template: "docs/meta/changelog.erb"
end
# rubocop:enable Metrics/BlockLength
