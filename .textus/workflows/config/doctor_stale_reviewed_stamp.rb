# Replaces Doctor::Check::StaleReviewedStamp. Warns when knowledge docs have
# reviewed stamps too far behind the current minor version.

# rubocop:disable Metrics/BlockLength
Textus.workflow "doctor-stale-reviewed-stamp" do
  match "artifacts.doctor.stale-reviewed-stamp"

  step :scan do |_, ctx|
    stamp_re = /\*\*reviewed\*\*\s+\d{4}-\d{2}\s+\(v(\d+\.\d+(?:\.\d+)?)\)/
    threshold = 5
    current_minor = Textus::VERSION.sub(/\Av/, "").split(".").map(&:to_i)[1] || 0
    issues = []

    ctx.manifest.resolver.enumerate.each do |row|
      next unless row[:key].to_s.start_with?("knowledge.")
      next unless row[:path] && File.file?(row[:path])

      body = File.read(row[:path])
      match = body.match(stamp_re)
      next if match.nil?

      reviewed_minor = match[1].sub(/\Av/, "").split(".").map(&:to_i)[1] || 0
      behind = current_minor - reviewed_minor
      next unless behind > threshold

      current_short = Textus::VERSION[/\A\d+\.\d+/]
      issues << {
        "code" => "stale_reviewed_stamp",
        "level" => "warning",
        "subject" => row[:key].to_s,
        "message" => "reviewed at v#{match[1]}; current is v#{Textus::VERSION} " \
                     "(#{behind} minor versions behind, threshold is #{threshold})",
        "fix" => "review the doc and update the stamp to: **reviewed** YYYY-MM (v#{current_short})",
      }
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
# rubocop:enable Metrics/BlockLength
