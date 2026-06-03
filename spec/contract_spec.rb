require "spec_helper"

RSpec.describe Textus::Contract do
  # A throwaway class that declares a contract, to test the DSL in isolation.
  let(:klass) do
    Class.new do
      extend Textus::Contract::DSL

      verb     :demo
      summary  "A demo verb."
      surfaces :cli, :mcp
      arg :key,  String, required: true, description: "the key"
      arg :flag, :boolean
      response { |v| { "echoed" => v } }
    end
  end

  it "exposes a frozen Spec" do
    expect(klass.contract?).to be(true)
    expect(klass.contract.verb).to eq(:demo)
    expect(klass.contract.summary).to eq("A demo verb.")
    expect(klass.contract.surfaces).to contain_exactly(:cli, :mcp)
    expect(klass.contract.mcp?).to be(true)
  end

  it "builds a JSON inputSchema from the args" do
    schema = klass.contract.input_schema
    expect(schema[:type]).to eq("object")
    expect(schema[:properties]["key"]).to eq("type" => "string", "description" => "the key")
    expect(schema[:properties]["flag"]).to eq("type" => "boolean")
    expect(schema[:required]).to eq(["key"])
  end

  it "exposes wire_name on the schema while keeping the kwarg name (ADR 0057)" do
    k = Class.new do
      extend Textus::Contract::DSL

      verb :w
      surfaces :mcp
      arg :meta, Hash, required: true, wire_name: :_meta, description: "frontmatter"
    end
    schema = k.contract.input_schema
    expect(schema[:properties]).to have_key("_meta")
    expect(schema[:properties]).not_to have_key("meta")
    expect(schema[:required]).to eq(["_meta"])
    # the kwarg name is unchanged — the use-case still receives `meta:`
    arg = k.contract.args.first
    expect(arg.name).to eq(:meta)
    expect(arg.wire).to eq(:_meta)
  end

  it "defaults wire_name to the arg name" do
    expect(klass.contract.args.first.wire).to eq(:key)
  end

  it "carries a response shaper, defaulting to identity" do
    expect(klass.contract.response.call("x")).to eq("echoed" => "x")
    plain = Class.new do
      extend Textus::Contract::DSL

      verb :p
    end
    expect(plain.contract.response.call(42)).to eq(42)
  end

  it "reports a class without a contract" do
    expect(Class.new.respond_to?(:contract?)).to be(false)
  end

  it "raises if arg or verb is called after .contract has been read" do
    klass.contract # trigger memoization
    expect { klass.arg(:extra, String) }.to raise_error(RuntimeError, /contract already built/)
    expect { klass.verb(:other) }.to raise_error(RuntimeError, /contract already built/)
  end

  it "carries session_default on an arg when declared" do
    k = Class.new do
      extend Textus::Contract::DSL

      verb :example
      arg :x, Integer, session_default: :cursor
    end
    a = k.contract.args.find { |arg| arg.name == :x }
    expect(a.session_default).to eq(:cursor)
  end

  it "session_default is nil by default" do
    a = klass.contract.args.find { |arg| arg.name == :key }
    expect(a.session_default).to be_nil
  end

  it "an arg can declare a literal default (ADR 0062 amendment)" do
    klass = Class.new do
      extend Textus::Contract::DSL

      verb :demo
      arg :key, String, required: true, positional: true
      arg :flag, :boolean, default: true
    end
    flag = klass.contract.args.find { |a| a.name == :flag }
    expect(flag.default).to be(true)
  end

  describe "cli facet" do
    def build(&blk)
      Class.new do
        extend Textus::Contract::DSL

        class_eval(&blk)
      end.contract
    end

    it "defaults the cli path to the verb token when :cli is surfaced and no path is declared" do
      spec = build do
        verb :where
        surfaces :cli, :ruby, :mcp
        arg :key, String, required: true, positional: true
      end
      expect(spec.cli?).to be true
      expect(spec.cli_path).to eq("where")
      expect(spec.cli_group).to be_nil
      expect(spec.cli_leaf).to eq("where")
    end

    it "honors an explicit grouped cli path and splits group/leaf" do
      spec = build do
        verb :schema_show
        surfaces :cli, :ruby, :mcp
        cli "schema show"
        arg :key, String, required: true, positional: true
      end
      expect(spec.cli_path).to eq("schema show")
      expect(spec.cli_group).to eq("schema")
      expect(spec.cli_leaf).to eq("show")
    end

    it "reports cli? false when :cli is not a surface" do
      spec = build do
        verb :secret
        surfaces :ruby, :mcp
      end
      expect(spec.cli?).to be false
    end

    it "stores a cli_response block, defaulting to nil" do
      plain = build do
        verb :where
        surfaces :cli, :ruby
        arg :key, String, positional: true
      end
      expect(plain.cli_response).to be_nil

      wrapped = build do
        verb :list
        surfaces :cli, :ruby
        cli_response { |rows| { "entries" => rows } }
      end
      expect(wrapped.cli_response.call([1, 2])).to eq({ "entries" => [1, 2] })
    end
  end
end
