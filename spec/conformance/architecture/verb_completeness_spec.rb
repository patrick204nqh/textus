# rubocop:disable RSpec/LeakyConstantDeclaration, Lint/ConstantDefinitionInBlock
RSpec.describe "Verb completeness — every verb has contract + handler + CLI verb" do
  VERB_REGISTRY = Textus::VerbRegistry.registered.to_h { |s| [s.verb, s] }.freeze

  def handled_contracts
    all_handles = []
    [Textus::UseCases::Read, Textus::UseCases::Write, Textus::UseCases::Ops].each do |ns|
      ns.constants(false).each do |c|
        mod = ns.const_get(c)
        next unless mod.is_a?(Module) && mod.const_defined?(:HANDLES)

        handles = mod.const_defined?(:HANDLES_ALL) ? Array(mod::HANDLES_ALL) : [mod::HANDLES]
        all_handles.concat(handles)
      end
    end
    all_handles
  end

  it "every registered verb has a contract class" do
    missing = VERB_REGISTRY.keys.reject { |v| Textus::VerbRegistry.contract_class_for(v) }
    expect(missing).to be_empty,
                       "verbs without a contract: #{missing.map(&:inspect).join(", ")}"
  end

  it "every verb with CLI surface has a CLI verb class" do
    cli_verbs = Textus::Surface::CLI.verbs.keys.map(&:to_sym)
    cli_missing = VERB_REGISTRY.values
                               .select(&:cli?)
                               .map(&:verb)
                               .reject { |v| cli_verbs.include?(v) || cli_verb_alias?(v, cli_verbs) }
    expect(cli_missing).to be_empty,
                           "verbs with cli: true but no CLI verb class: #{cli_missing.map(&:inspect).join(", ")}"
  end

  it "every contract class has a use-case handler" do
    registered_contracts = VERB_REGISTRY.keys.map { |v| Textus::VerbRegistry.contract_class_for(v) }.compact.to_set
    handled = handled_contracts.to_set
    orphan_contracts = registered_contracts - handled
    expect(orphan_contracts).to be_empty,
                                "contracts without a handler: #{orphan_contracts.map(&:name).join(", ")}"
  end

  def cli_verb_alias?(verb, cli_verbs)
    spec = VERB_REGISTRY[verb]
    return false unless spec&.cli_path

    group_name = spec.cli_path.split.first&.to_sym
    cli_verbs.include?(group_name)
  end
end
# rubocop:enable RSpec/LeakyConstantDeclaration, Lint/ConstantDefinitionInBlock
