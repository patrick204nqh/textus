# Verifying doubles for collaborators that specs used to fake with anonymous
# `Class.new { def execute(*) = ... }` objects (a normal-double code smell —
# they pass even if the real interface changes). `instance_double` verifies the
# method exists on the real class.
module TextusDoubleHelpers
  # A FetchOrchestrator whose #execute returns `outcome` for any (action, key:).
  # Replaces the hand-rolled orchestrator fakes in the read/get path.
  #
  #   orch = stub_orchestrator(Textus::Domain::Outcome::Skipped.new)
  #   Textus::Read::Get.new(container:, call:, orchestrator: orch)
  def stub_orchestrator(outcome)
    instance_double(Textus::Write::FetchOrchestrator, execute: outcome)
  end
end

RSpec.configure { |c| c.include TextusDoubleHelpers }
