require "spec_helper"

# Step::Builtin / Step::RegistryStore were removed in the workflow redesign.
# The HTTP-JSON intake pattern is now implemented as a workflow step.
RSpec.describe "cookbook: http_json intake recipe" do
  it "is pending workflow-based reimplementation" do
    pending "step system removed; reimplement as Textus.workflow DSL test"
    raise "should be pending"
  end
end
