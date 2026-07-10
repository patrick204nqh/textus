RSpec.describe "Protocol::Format::Base contract" do
  classes = Textus::Protocol::Format::STRATEGIES.values.map(&:call)

  classes.each do |klass|
    context klass.name do
      it "implements core methods" do
        expect(klass).to respond_to(:parse)
        expect(klass).to respond_to(:serialize)
        expect(klass).to respond_to(:extensions)
      end

      it "provides data_to_payload (inherited or overridden)" do
        expect(klass).to respond_to(:data_to_payload)
      end

      it "provides format_payload (default from Base or custom)" do
        expect(klass).to respond_to(:format_payload)
      end
    end
  end

  it "Base provides the template method" do
    expect(Textus::Protocol::Format::Base).to respond_to(:data_to_payload)
  end
end
