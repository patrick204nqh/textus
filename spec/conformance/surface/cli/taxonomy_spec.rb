require "spec_helper"

RSpec.describe "hand-authored CLI verb taxonomy" do
  before { Textus::Surface::CLI::Runner.install! }

  def cli_class_for(verb)
    leaf = Textus::Action::VERBS[verb].contract.cli_leaf
    Textus::Surface::CLI::Verb.descendants.find { |k| k.respond_to?(:command_name) && k.command_name == leaf }
  end

  it "every BEHAVIORAL_HATCHES verb has a Runner::Base subclass (a real override)" do
    Textus::Surface::CLI::Runner::BEHAVIORAL_HATCHES.each do |verb|
      klass = cli_class_for(verb)
      expect(klass).to be < Textus::Surface::CLI::Runner::Base, "#{verb} should be a Runner::Base behavioral hatch"
    end
  end

  it "every NON_PROJECTED_CLI verb has a plain Verb subclass (not Runner::Base)" do
    Textus::Surface::CLI::Runner::NON_PROJECTED_CLI.each do |verb|
      klass = cli_class_for(verb)
      expect(klass).not_to be < Textus::Surface::CLI::Runner::Base, "#{verb} should be a non-projected < Verb command"
    end
  end

  it "the union still equals the full exclusion set the installer honors" do
    union = (Textus::Surface::CLI::Runner::BEHAVIORAL_HATCHES + Textus::Surface::CLI::Runner::NON_PROJECTED_CLI).sort
    expect(Textus::Surface::CLI::Runner::HAND_AUTHORED_VERBS.sort).to eq(union)
  end
end
