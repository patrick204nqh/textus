# rubocop:disable Metrics/BlockLength
Textus.workflow "changelog" do
  match "artifacts.changelog"

  step :build do |_, _|
    # skip: merge commits, and housekeeping drain commits that would otherwise
    # create a self-referential loop (drain produces a commit → commit appears
    # in changelog → drain produces a new file → repeat).
    skip_pattern = /\A(chore: textus drain|Merge )/

    raw = `git log --no-merges --pretty=format:"%D|||%s|||%ad" --date=short 2>/dev/null`.strip
    lines = raw.split("\n").map { |l| l.split("|||") }

    entries = []
    current_tag = "Unreleased"
    current_date = nil
    current_commits = []

    flush = lambda do
      entries << { "tag" => current_tag, "date" => current_date, "commits" => current_commits.dup } unless current_commits.empty?
      current_commits = []
    end

    lines.each do |refs, subject, date|
      tag = refs.to_s.scan(/tag: (v[\d.]+)/).flatten.first
      if tag
        flush.call
        current_tag = tag
        current_date = date.to_s.strip
      end
      next unless subject && !subject.to_s.strip.match?(skip_pattern)

      current_commits << { "subject" => subject.to_s.strip, "date" => date.to_s.strip }
    end
    flush.call

    { "content" => { "entries" => entries } }
  end

  publish
end
# rubocop:enable Metrics/BlockLength
