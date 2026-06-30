# rubocop:disable Metrics/BlockLength
Textus.workflow "changelog" do
  match "artifacts.changelog"

  step :build do |_, _|
    require "digest"

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
      current_commits << { "subject" => subject.to_s.strip, "date" => date.to_s.strip } if subject
    end
    flush.call

    uid = Digest::SHA1.hexdigest(entries.map { |e| e["tag"] }.join)[0, 16]
    { "_meta" => { "uid" => uid }, "content" => { "entries" => entries } }
  end

  publish
end
# rubocop:enable Metrics/BlockLength
