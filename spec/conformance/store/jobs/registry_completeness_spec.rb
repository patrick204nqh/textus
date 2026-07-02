RSpec.describe "Jobs registry — every entry is a callable" do
  it "all registry entries respond to call" do
    Textus::Store::Jobs::Registry::JOBS.each do |type, fn|
      expect(fn).to respond_to(:call), "#{type} is not callable"
    end
  end

  it "every required_role entry has a matching job type" do
    Textus::Store::Jobs::Registry::REQUIRED_ROLES.each_key do |type|
      expect(Textus::Store::Jobs::Registry::JOBS).to have_key(type),
                                                     "REQUIRED_ROLES references unknown job type: #{type}"
    end
  end

  it "lists at least one job type" do
    expect(Textus::Store::Jobs::Registry::JOBS.keys).not_to be_empty
  end
end
