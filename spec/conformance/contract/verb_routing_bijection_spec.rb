require "spec_helper"

# ADR 0105 — the verb token is declared twice: once as a `Dispatcher::VERBS`
# routing key, once via `verb :foo` in the use case's Contract DSL. Nothing
# couples the two, so a use case could declare a verb it is never routed under,
# or be routed under a key that disagrees with its contract. This is a
# gem-internal invariant (a user's store cannot change `Dispatcher::VERBS`), so
# it is enforced here as a build-time bijection, not as a per-store doctor check.
RSpec.describe "verb routing bijection (ADR 0105)" do
  # Every use case that declares a contract. `eager_load` (lib/textus.rb) has
  # already loaded the whole gem by the time any spec runs, so ObjectSpace sees
  # the full set. Restricted to real `Textus::` constants to exclude anonymous
  # or test-defined contract classes a sibling spec might have left behind.
  def contract_use_cases
    routed_actions = Textus::Action::VERBS.values.select { |klass| klass <= Textus::Action::Base }

    ObjectSpace.each_object(Class).select do |klass|
      klass.name&.start_with?("Textus::") &&
        klass.respond_to?(:contract?) && klass.contract?
    end.reject do |klass|
      routed_actions.any? { |action| action.contract.verb == klass.contract.verb && action != klass }
    end
  end

  describe "forward — every route points at the class that claims it" do
    Textus::Action::VERBS.each do |verb_sym, klass|
      describe "#{verb_sym} -> #{klass}" do
        it "resolves to a class that declares a contract" do
          expect(klass.respond_to?(:contract?) && klass.contract?)
            .to be(true), "#{klass} is routed for :#{verb_sym} but declares no `verb` in its Contract DSL"
        end

        it "declares the verb it is routed under" do
          expect(klass.contract.verb).to eq(verb_sym),
                                         "Dispatcher routes :#{verb_sym} to #{klass}, " \
                                         "but that class declares `verb :#{klass.contract.verb}` — the routing key and the " \
                                         "contract disagree"
        end
      end
    end
  end

  describe "reverse — every declared verb is routed (no declare-but-unrouted)" do
    it "registers every contract use case in Dispatcher::VERBS" do
      registered = Textus::Action::VERBS.values
      unrouted   = contract_use_cases.reject { |klass| registered.include?(klass) }

      expect(unrouted).to be_empty,
                          "these classes declare a `verb` but are not in Dispatcher::VERBS " \
                          "(add the route, or remove the contract): " \
                          "#{unrouted.map { |k| "#{k} (verb :#{k.contract.verb})" }.join(", ")}"
    end
  end

  describe "totality — the map is a function and an injection" do
    it "routes each verb symbol to exactly one class (no duplicate values)" do
      classes = Textus::Action::VERBS.values
      dupes = classes.tally.select { |_klass, n| n > 1 }.keys
      expect(dupes).to be_empty,
                       "these use-case classes are routed under more than one verb: #{dupes.join(", ")}"
    end

    it "keys agree with each class's declared verb set (round-trips)" do
      from_routes    = Textus::Action::VERBS.keys.sort
      from_contracts = Textus::Action::VERBS.values.map { |k| k.contract.verb }.sort
      expect(from_routes).to eq(from_contracts)
    end
  end
end
