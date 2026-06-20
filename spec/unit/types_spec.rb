require "spec_helper"

RSpec.describe Textus::Value::Types do
  it "rejects an invalid role name" do
    expect { Textus::Value::Types::RoleName["nope"] }.to raise_error(Dry::Types::ConstraintError)
  end

  it "accepts a valid role name" do
    expect(Textus::Value::Types::RoleName["human"]).to eq("human")
  end

  it "rejects a negative cursor" do
    expect { Textus::Value::Types::Cursor[-1] }.to raise_error(Dry::Types::ConstraintError)
  end

  it "accepts zero cursor" do
    expect(Textus::Value::Types::Cursor[0]).to eq(0)
  end
end
