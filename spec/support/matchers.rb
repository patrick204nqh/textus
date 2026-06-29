# Asserts the block raises Textus::GuardFailed naming (at least) the given
# unmet predicate(s). Replaces the repeated
#   raise_error(Textus::GuardFailed) { |e| e.details["failed"].map { ... } }
# dig. GuardFailed always carries the "guard_failed" code, so callers no
# longer need a separate code assertion.
#
#   expect { store.with_role("agent").accept(key) }.to fail_guard_with("author_held")
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

# Parses and returns the last row of the store's audit.log as a Hash.
# Raises if the log is missing/empty — that's a real test failure, not a nil.
module TextusAuditHelpers
  def last_audit_row(store)
    log = Textus::Store::Geometry.new(store.root).audit_log_path
    JSON.parse(File.readlines(log).last)
  end
end
RSpec.configure { |c| c.include TextusAuditHelpers }

# Asserts the last audit row records the given verb, optionally with a
# correlation_id (matched against extras.correlation_id):
#
#   expect(store).to have_audit_verb("put")
#   expect(store).to have_audit_verb("delete").with_correlation("corr-1")
RSpec::Matchers.define :have_audit_verb do |verb|
  chain(:with_correlation) { |cid| @cid = cid }

  match do |store|
    log = Textus::Store::Geometry.new(store.root).audit_log_path
    next false unless File.exist?(log) && !File.empty?(log)

    @row = JSON.parse(File.readlines(log).last)
    next false unless @row["verb"] == verb

    @cid.nil? || @row.dig("extras", "correlation_id") == @cid
  end

  failure_message do
    cid_part = @cid ? " correlation_id=#{@cid.inspect}" : nil
    target = "verb=#{verb.inspect}#{cid_part}"
    "expected last audit row to be #{target}, got #{@row.inspect}"
  end
end

# Result matchers for Textus::Value::Result (was Dry::Monads, replaced by ADR 0119 migration).
#   expect(handler.call(...)).to be_success
#   expect(handler.call(...)).to be_failure
RSpec::Matchers.define :be_success do
  match { |actual| actual.is_a?(Textus::Value::Result) && actual.success? }

  failure_message do |actual|
    if actual.is_a?(Textus::Value::Result)
      "expected Success, got Failure(#{actual.error.inspect})"
    else
      "expected Success, got #{actual.class}"
    end
  end
end

RSpec::Matchers.define :be_failure do
  match { |actual| actual.is_a?(Textus::Value::Result) && actual.failure? }

  failure_message do |actual|
    if actual.is_a?(Textus::Value::Result)
      "expected Failure, got Success(#{actual.value.inspect})"
    else
      "expected Failure, got #{actual.class}"
    end
  end
end
