$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

# Coverage is opt-in (COVERAGE=1) so the default run stays fast and CI is
# unaffected. It must start before `require "textus"` to instrument lib/.
# The report it produces is the evidence base for retiring low-value specs.
if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    enable_coverage :branch
    add_filter "/spec/"
    track_files "lib/**/*.rb"
  end
end

# Stdlib used pervasively across the suite. Required here once so individual
# specs don't repeat `require "tmpdir"` / "fileutils" / "json" / "yaml".
require "tmpdir"
require "fileutils"
require "json"
require "yaml"

require "textus"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

RSpec.configure do |c|
  c.expect_with(:rspec) { |e| e.syntax = :expect }
  c.disable_monkey_patching!
  c.order = :random
  Kernel.srand c.seed

  # Category tags are DERIVED from the spec's directory (single source: its
  # location), so `rspec --tag unit` / `--tag integration` / `--tag conformance`
  # partition the suite with no hand-maintained metadata. No-op until the
  # Phase-1 move populates spec/{unit,integration,conformance}/.
  c.define_derived_metadata(file_path: %r{/spec/unit/})        { |m| m[:unit]        = true }
  c.define_derived_metadata(file_path: %r{/spec/integration/}) { |m| m[:integration] = true }
  c.define_derived_metadata(file_path: %r{/spec/conformance/}) { |m| m[:conformance] = true }

  # ADR 0087: a canon `put` triggers an async derived rebuild on a tracked,
  # join-before-exit thread (ReactiveMaterialize::AsyncRunner). Join any
  # straggler before the next example so threads never leak across examples.
  # Fixtures that own a tmpdir drain in their own teardown (before removing the
  # dir) to avoid an in-flight rebuild racing `remove_entry` (`ENOTEMPTY`); this
  # is the test-side mirror of the production `at_exit` drain.
  c.before { Textus::Maintenance::ReactiveMaterialize::AsyncRunner.drain }
end
