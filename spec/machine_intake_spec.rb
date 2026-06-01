require "spec_helper"
require "textus/init/templates/machine_intake_logic" # pure core

RSpec.describe "machine intake scaffold" do
  it "builds the safe-scalar allowlist and nothing else" do
    content = Textus::Scaffold::MachineIntake.call(
      git: { head: "abc1234", branch: "main", dirty: false, root: "/repo" },
      now: "2026-06-01T00:00:00Z",
    )
    expect(content.keys).to contain_exactly(
      "git_head", "git_branch", "git_dirty", "repo_root",
      "captured_at", "ruby_version", "os", "textus_version", "protocol"
    )
    expect(content["protocol"]).to eq(Textus::PROTOCOL)
    expect(content["textus_version"]).to eq(Textus::VERSION)
  end

  it "never emits raw environment variables" do
    content = Textus::Scaffold::MachineIntake.call(
      git: { head: "x", branch: "y", dirty: true, root: "/r" },
      now: "2026-06-01T00:00:00Z",
    )
    expect(content.values.join).not_to include(ENV.fetch("HOME", "/Users"))
    expect(content.keys).not_to include("env")
  end
end
