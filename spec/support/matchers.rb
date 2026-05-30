# Asserts the block raises Textus::GuardFailed naming (at least) the given
# unmet predicate(s). Replaces the repeated
#   raise_error(Textus::GuardFailed) { |e| e.details["failed"].map { ... } }
# dig. GuardFailed always carries the "guard_failed" code, so callers no
# longer need a separate code assertion.
#
#   expect { store.as("agent").accept(key) }.to fail_guard_with("accept_signed")
RSpec::Matchers.define :fail_guard_with do |*predicates|
  supports_block_expectations

  match do |block|
    block.call
    @raised = false
  rescue Textus::GuardFailed => e
    @raised = true
    @unmet = e.details["failed"].map { |f| f["predicate"] }
    predicates.all? { |p| @unmet.include?(p) }
  end

  failure_message do
    if @raised
      "expected unmet predicates #{@unmet.inspect} to include #{predicates.inspect}"
    else
      "expected GuardFailed naming #{predicates.inspect}, but no GuardFailed was raised"
    end
  end
end
