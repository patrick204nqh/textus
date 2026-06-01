# .textus/hooks/machine_intake.rb
# Scaffolded by `textus init` — CUSTOMIZE FREELY, or delete the feeds.machine
# entry from manifest.yaml if you don't want it.
# Feeds a SNAPSHOT of this host into feeds.machine on `textus fetch`. The entry
# is tracked:false (gitignored) because machine info can be sensitive/noisy —
# NEVER add secrets / full ENV here.
Textus.hook do |reg|
  reg.on(:resolve_intake, :machine) do |config:, **|
    _ = config
    sh = ->(cmd) { `#{cmd}`.strip }                         # local shell-out, no network
    { content: {
      "git_head"       => sh.call("git rev-parse --short HEAD 2>/dev/null"),
      "git_branch"     => sh.call("git rev-parse --abbrev-ref HEAD 2>/dev/null"),
      "git_dirty"      => !sh.call("git status --porcelain 2>/dev/null").empty?,
      "repo_root"      => sh.call("git rev-parse --show-toplevel 2>/dev/null"),
      "captured_at"    => Time.now.utc.iso8601,
      "ruby_version"   => RUBY_VERSION,
      "os"             => RbConfig::CONFIG["host_os"],
      "textus_version" => Textus::VERSION,
      "protocol"       => Textus::PROTOCOL,
    } }
  end
end
