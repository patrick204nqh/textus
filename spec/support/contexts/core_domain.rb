RSpec.shared_context "core domain doubles" do
  let(:frozen_now) { Time.parse("2026-01-01 12:00:00 UTC") }
  let(:fake_clock) { instance_double(Textus::Port::Clock, now: frozen_now) }
  let(:file_registry) { {} }

  let(:fake_file_stat) do
    instance_double(Textus::Port::Storage::FileStat).tap do |s|
      allow(s).to receive(:exists?)    { |p| file_registry.key?(p) }
      allow(s).to receive(:mtime)      { |p| file_registry.fetch(p, {})[:mtime] }
      allow(s).to receive(:read)       { |p| file_registry.fetch(p, {})[:content] || "" }
      allow(s).to receive_messages(directory?: false, glob: [])
    end
  end

  def register_file(path, content: "", mtime: nil)
    mtime ||= frozen_now - 3600
    file_registry[path] = { content: content, mtime: mtime }
  end
end
