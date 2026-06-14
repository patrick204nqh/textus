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

  # Specs that exercise actively-changing internals are marked volatile so
  # contract-focused suites can exclude them by policy.
  c.define_derived_metadata(file_path: %r{/spec/conformance/events_spec\.rb$}) { |m| m[:volatile] = true }
  c.define_derived_metadata(file_path: %r{/spec/conformance/loaded_event_spec\.rb$}) { |m| m[:volatile] = true }
  c.define_derived_metadata(file_path: %r{/spec/conformance/publish/tree_spec\.rb$}) { |m| m[:volatile] = true }
  c.define_derived_metadata(file_path: %r{/spec/conformance/plugin_manifest_build_spec\.rb$}) { |m| m[:volatile] = true }
  c.define_derived_metadata(file_path: %r{/spec/conformance/init/scaffold_spec\.rb$}) { |m| m[:volatile] = true }
  c.define_derived_metadata(file_path: %r{/spec/conformance/write/mv_spec\.rb$}) { |m| m[:volatile] = true }
  c.define_derived_metadata(file_path: %r{/spec/conformance/write/reject_spec\.rb$}) { |m| m[:volatile] = true }
  c.define_derived_metadata(file_path: %r{/spec/conformance/cli/(hook_verbs|action_verb|groups|contract|root_flag)_spec\.rb$}) do |m|
    m[:volatile] = true
  end
  c.define_derived_metadata(file_path: %r{/spec/unit/produce/events_spec\.rb$}) { |m| m[:volatile] = true }
  c.define_derived_metadata(file_path: %r{/spec/unit/spec_layout_spec\.rb$}) { |m| m[:volatile] = true }
  c.define_derived_metadata(file_path: %r{/spec/conformance/boot/cli_verbs_spec\.rb$}) { |m| m[:volatile] = true }

  c.define_derived_metadata(file_path: %r{/spec/(unit|integration)/dispatch/}) { |m| m[:volatile] = true }

  c.define_derived_metadata(file_path: %r{/spec/unit/surfaces/}) { |m| m[:volatile] = true }
end
