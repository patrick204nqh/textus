module Textus
  module Scaffold
    # Pure: given already-gathered ambient facts, return the safe-scalar Hash.
    # No I/O, no secrets — deterministic and unit-testable. The scaffolded
    # `:resolve_intake` hook gathers `git`/`now` via shell-outs and delegates the
    # shape to this allowlist (ADR 0043).
    module MachineIntake
      module_function

      def call(git:, now:)
        {
          "git_head"       => git[:head],
          "git_branch"     => git[:branch],
          "git_dirty"      => git[:dirty],
          "repo_root"      => git[:root],
          "captured_at"    => now,
          "ruby_version"   => RUBY_VERSION,
          "os"             => RbConfig::CONFIG["host_os"],
          "textus_version" => Textus::VERSION,
          "protocol"       => Textus::PROTOCOL,
        }
      end
    end
  end
end
