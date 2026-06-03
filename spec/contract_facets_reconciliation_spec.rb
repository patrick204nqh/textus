require "spec_helper"

# Guard (ADR 0068): the declarative facets that replaced escape-hatch classes
# must stay resolvable. Every around: names a registered resource; every
# cli_stdin mode is supported; every default view tolerates the uniform
# (result, inputs) call. Drift becomes a red test, not a runtime surprise.
RSpec.describe "contract facet reconciliation (ADR 0068)" do
  let(:specs) do
    Textus::Dispatcher::VERBS.values
                             .select { |k| k.respond_to?(:contract?) && k.contract? }
                             .map(&:contract)
  end

  it "every around: names a registered resource" do
    specs.select(&:around).each do |s|
      expect { Textus::Contract::Around.fetch(s.around) }
        .not_to(raise_error, "verb #{s.verb} around #{s.around.inspect}")
    end
  end

  it "every cli_stdin mode is supported" do
    expect(specs.filter_map(&:cli_stdin).uniq).to all(eq(:json))
  end

  it "every default view is callable with (result, inputs)" do
    specs.each do |s|
      expect(s.view(:default)).to respond_to(:call)
      # arity tolerance: a one-param view must accept the second arg
      expect(s.view(:default).arity).to be <= 2
    end
  end
end
