module Textus
  module Doctor
    class Check
      # Warns when a knowledge-lane doc's `**reviewed** YYYY-MM (vX.Y)` stamp
      # is more than MINOR_THRESHOLD minor versions behind Textus::VERSION.
      # The stamp is the human staleness signal declared in docs conventions
      # (knowledge.docs-index); this check makes it machine-enforced.
      class StaleReviewedStamp < Check
        STAMP_RE = /\*\*reviewed\*\*\s+\d{4}-\d{2}\s+\(v(\d+\.\d+(?:\.\d+)?)\)/
        MINOR_THRESHOLD = 5

        def call
          current_minor = parse_minor(Textus::VERSION)
          issues = []

          manifest.resolver.enumerate.each do |row|
            next unless row[:key].to_s.start_with?("knowledge.")
            next unless row[:path] && File.file?(row[:path])

            body = File.read(row[:path])
            m = body.match(STAMP_RE)
            next unless m

            reviewed_minor = parse_minor(m[1])
            behind = current_minor - reviewed_minor
            next unless behind > MINOR_THRESHOLD

            issues << stale_issue(row[:key], m[1], behind)
          end

          issues
        end

        private

        def parse_minor(version_str)
          version_str.sub(/\Av/, "").split(".").map(&:to_i)[1] || 0
        end

        def stale_issue(key, stamp_version, behind)
          current_short = Textus::VERSION[/\A\d+\.\d+/]
          {
            "code" => "stale_reviewed_stamp",
            "level" => "warning",
            "subject" => key.to_s,
            "message" => "reviewed at v#{stamp_version}; current is v#{Textus::VERSION} " \
                         "(#{behind} minor versions behind, threshold is #{MINOR_THRESHOLD})",
            "fix" => "review the doc and update the stamp to: **reviewed** YYYY-MM (v#{current_short})",
          }
        end
      end
    end
  end
end
