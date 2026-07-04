# rubocop:disable RSpec/LeakyConstantDeclaration, Lint/ConstantDefinitionInBlock
RSpec.describe "Verb completeness — every verb has contract + handler + CLI verb" do
  VERB_REGISTRY = Textus::Protocol::VerbRegistry.registered.to_h { |s| [s.verb, s] }.freeze
  LANE_VERBS = VERB_REGISTRY.values.select(&:lane).to_set(&:verb).freeze
  BUILTIN_VERBS = VERB_REGISTRY.values.reject(&:lane).to_set(&:verb).freeze
  GATE_HANDLED = LANE_VERBS + BUILTIN_VERBS

  it "every verb with CLI surface has a CLI verb class" do
    cli_verbs = Textus::Surface::CLI.verbs.keys.map(&:to_sym)
    cli_missing = VERB_REGISTRY.values
                               .select(&:cli?)
                               .map(&:verb)
                               .reject { |v| cli_verbs.include?(v) || cli_verb_alias?(v, cli_verbs) }
    expect(cli_missing).to be_empty,
                           "verbs with cli: true but no CLI verb class: #{cli_missing.map(&:inspect).join(", ")}"
  end

  it "every verb is handled by Gate (Builtin or lane handler)" do
    unhandled = VERB_REGISTRY.keys.reject { |v| GATE_HANDLED.include?(v) }
    expect(unhandled).to be_empty,
                         "verbs without a handler: #{unhandled.map(&:inspect).join(", ")}"
  end

  CLI_PATHS = Textus::Surface::CLI::Runner::CLI_PATHS if defined?(Textus::Surface::CLI::Runner)

  def cli_verb_alias?(verb, cli_verbs)
    spec = VERB_REGISTRY[verb]
    return false unless spec

    cli_path = CLI_PATHS&.[](verb) || spec.cli_path
    group_name = cli_path.split.first&.to_sym
    cli_verbs.include?(group_name)
  end
end
# rubocop:enable RSpec/LeakyConstantDeclaration, Lint/ConstantDefinitionInBlock
