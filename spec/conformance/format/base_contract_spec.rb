RSpec.describe "Protocol::Format::Base contract" do
  classes = Textus::Protocol::Format::STRATEGIES.values.map(&:call)

  classes.each do |klass|
    context klass.name do
      it "implements core methods" do
        expect(klass).to respond_to(:parse)
        expect(klass).to respond_to(:serialize)
        expect(klass).to respond_to(:extensions)
      end

      it "does not inherit data_to_payload from Base" do
        expect(Textus::Protocol::Format::Base).not_to respond_to(:data_to_payload)
      end
    end
  end
end
