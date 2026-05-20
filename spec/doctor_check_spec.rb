require "spec_helper"
require "tmpdir"

RSpec.describe "registered doctor_check invocation" do
  def init_store(dir)
    root = File.join(dir, ".textus")
    Textus::Init.run(root)
    root
  end

  it "merges registered check issues into the doctor report" do
    Dir.mktmpdir do |dir|
      root = init_store(dir)
      File.write(File.join(root, "extensions/org_rules.rb"), <<~RUBY)
        Textus.doctor_check(:org_rules) do |store:|
          [{ "code" => "org.bad_naming", "level" => "warning",
             "subject" => "test", "message" => "fake issue", "fix" => "n/a" }]
        end
      RUBY

      store = Textus::Store.new(root)
      report = Textus::Doctor.run(store)
      codes = report["issues"].map { |i| i["code"] }
      expect(codes).to include("org.bad_naming")
      expect(report["summary"]["warning"]).to be >= 1
    end
  end

  it "captures a check that raises as an error-level issue without aborting" do
    Dir.mktmpdir do |dir|
      root = init_store(dir)
      File.write(File.join(root, "extensions/boom.rb"), <<~RUBY)
        Textus.doctor_check(:boom) { |store:| raise "kaboom" }
      RUBY

      store = Textus::Store.new(root)
      report = Textus::Doctor.run(store)
      boom = report["issues"].find { |i| i["code"] == "doctor_check.failed" }
      expect(boom).not_to be_nil
      expect(boom["subject"]).to eq("boom")
      expect(boom["message"]).to match(/kaboom/)
    end
  end

  it "captures a check that times out" do
    Dir.mktmpdir do |dir|
      root = init_store(dir)
      File.write(File.join(root, "extensions/slow.rb"), <<~RUBY)
        Textus.doctor_check(:slow) { |store:| :unreached }
      RUBY

      allow(Timeout).to receive(:timeout).and_call_original
      allow(Timeout).to receive(:timeout)
        .with(Textus::Doctor::DOCTOR_CHECK_TIMEOUT_SECONDS)
        .and_raise(Timeout::Error)

      store = Textus::Store.new(root)
      report = Textus::Doctor.run(store)
      slow = report["issues"].find { |i| i["code"] == "doctor_check.timeout" }
      expect(slow).not_to be_nil
      expect(slow["subject"]).to eq("slow")
    end
  end
end
