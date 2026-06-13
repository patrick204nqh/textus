# .textus/steps/fetch/machine_intake.rb
# Scaffolded by `textus init` — CUSTOMIZE FREELY, or delete the feeds.machines
# entry from manifest.yaml if you don't want it.
# Feeds a per-host SNAPSHOT into feeds.machines.<host> on `textus drain`
# (never on the per-turn boot/pulse path). It is NESTED so it grows to a fleet: the
# `local` leaf scans THIS host; add ssh hosts with the cookbook recipe
# (docs/cookbook/environment-scan.md). tracked:false → gitignored. Keep this an
# ALLOWLIST of versions and counts — NEVER secrets, raw `env`, or package lists.
module Textus
  module Step
    class MachineIntakeFetch < Fetch
      def call(config:, args:, caps:, **)
        machine = args[:leaf_segments].first or
          raise "machines intake needs a host leaf, e.g. the 'local' in feeds.machines.local"
        spec = (config["machines"] || {}).fetch(machine) { raise "unknown machine: #{machine}" }
        unless (spec["via"] || "local").to_s == "local"
          raise "machine #{machine}: only `via: local` is scaffolded — see " \
                "docs/cookbook/environment-scan.md for the SSH (remote) fan-out"
        end

        sh    = ->(cmd) { `#{cmd}`.strip }                      # local shell-out, no network
        ver   = ->(cmd) { o = `#{cmd} 2>/dev/null`.strip; o.empty? ? nil : o } # nil if tool absent
        count = ->(cmd) { n = `#{cmd} 2>/dev/null`.strip.lines.size; n.zero? ? nil : n }
        { content: {
          # git_* describe THIS repo on the control host — only meaningful for `local`.
          "git_head"       => sh.call("git rev-parse --short HEAD 2>/dev/null"),
          "git_branch"     => sh.call("git rev-parse --abbrev-ref HEAD 2>/dev/null"),
          "git_dirty"      => !sh.call("git status --porcelain 2>/dev/null").empty?,
          "repo_root"      => sh.call("git rev-parse --show-toplevel 2>/dev/null"),
          "captured_at"    => Time.now.utc.iso8601,
          "os"             => RbConfig::CONFIG["host_os"],
          "arch"           => RbConfig::CONFIG["host_cpu"],
          "ruby_version"   => RUBY_VERSION,
          "runtimes"       => {                                 # versions only; nil when not installed
            "node"   => ver.call("node --version"),
            "python" => ver.call("python3 --version"),
            "go"     => ver.call("go version"),
          },
          "packages"       => {                                 # COUNTS only — never the list (size/secrets)
            "brew" => count.call("brew list --formula"),        # ~1-3s on macOS; runs only on fetch, amortized by the ttl rule
            "apt"  => count.call("dpkg-query -f '.\n' -W"),
          },
          "textus_version" => Textus::VERSION,
          "protocol"       => Textus::PROTOCOL,
        } }
      end
    end
  end
end
