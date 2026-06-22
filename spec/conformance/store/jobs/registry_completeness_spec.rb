RSpec.describe "Jobs registry — every Job subclass is registered" do
  def all_job_classes
    Textus::Store::Jobs::Base.subclasses.flat_map { |k| [k] + k.subclasses }
  end

  it "every Store::Jobs::Base subclass appears in the registry" do
    registered = Textus::Store::Jobs::Registry::JOBS.values
    subclasses = all_job_classes
    unregistered = subclasses - registered
    expect(unregistered).to be_empty,
                            "Unregistered job subclasses: #{unregistered.map(&:name).join(", ")}"
  end

  it "every registry entry is a valid Job subclass" do
    Textus::Store::Jobs::Registry::JOBS.each_value do |klass|
      expect(klass).to be < Textus::Store::Jobs::Base
    end
  end
end
