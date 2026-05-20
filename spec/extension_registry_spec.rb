require "spec_helper"

RSpec.describe Textus::ExtensionRegistry do
  let(:reg) { described_class.new }
  let(:noop) { proc { :noop } }

  describe "actions" do
    it "registers and looks up an action" do
      reg.register_action(:github_repos) { |config:, store:, args:| [config, store, args].last && { frontmatter: {}, body: "" } }
      expect(reg.action(:github_repos)).to be_a(Proc)
    end

    it "raises usage error for unknown action" do
      expect { reg.action(:nope) }
        .to raise_error(Textus::UsageError, /unknown action: nope/)
    end

    it "lists registered actions by name" do
      reg.register_action(:a, &noop)
      reg.register_action(:b, &noop)
      expect(reg.action_names).to contain_exactly(:a, :b)
    end
  end

  describe "reducers" do
    it "registers and looks up a reducer" do
      reg.register_reducer(:top) { |rows:, config:| [config, rows.first(10)].last }
      expect(reg.reducer(:top)).to be_a(Proc)
    end

    it "raises usage error for unknown reducer" do
      expect { reg.reducer(:nope) }
        .to raise_error(Textus::UsageError, /unknown reducer: nope/)
    end
  end

  describe "hooks" do
    it "registers multiple hooks per event" do
      reg.register_hook(:refresh, :h1, &noop)
      reg.register_hook(:refresh, :h2, &noop)
      expect(reg.hooks(:refresh).map { |h| h[:name] }).to eq(%i[h1 h2])
    end

    it "returns empty array for an event with no hooks" do
      expect(reg.hooks(:build)).to eq([])
    end

    it "rejects unknown event names" do
      expect { reg.register_hook(:nonsense, :h, &noop) }
        .to raise_error(Textus::UsageError, /unknown event: nonsense/)
    end

    it "does not auto-register events merely by being queried" do
      reg.hooks(:build)
      reg.hooks(:put)
      expect(reg.hook_events).to be_empty
    end
  end

  describe "duplicate registration" do
    it "raises on duplicate action name" do
      reg.register_action(:dup, &noop)
      expect { reg.register_action(:dup, &noop) }
        .to raise_error(Textus::UsageError, /action 'dup' already registered/)
    end
  end

  describe "doctor_checks" do
    it "registers and retrieves doctor_check blocks" do
      reg = Textus::ExtensionRegistry.new
      reg.register_doctor_check(:org_rules) { |store:| [store].clear }
      expect(reg.doctor_check(:org_rules)).to be_a(Proc)
      expect(reg.doctor_check_names).to contain_exactly(:org_rules)
    end

    it "raises on duplicate doctor_check name" do
      reg = Textus::ExtensionRegistry.new
      noop = proc { |store:| [store].clear }
      reg.register_doctor_check(:dup, &noop)
      expect { reg.register_doctor_check(:dup, &noop) }
        .to raise_error(Textus::UsageError, /already registered/)
    end
  end
end
