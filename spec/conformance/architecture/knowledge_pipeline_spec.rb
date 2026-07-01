RSpec.describe "Knowledge pipeline conformance" do
  KNOWN_SECTIONS = %w[
    goals rules architecture decisions patterns runbooks specs readme project
  ].freeze

  def knowledge_dir
    File.expand_path("../../../.textus/data/knowledge", __dir__)
  end

  it "every knowledge section is a known section" do
    sections = Dir.children(knowledge_dir).select { |e| File.directory?(File.join(knowledge_dir, e)) }
    unknown = sections - KNOWN_SECTIONS
    expect(unknown).to be_empty,
                       "unknown knowledge sections: #{unknown.join(", ")}"
  end

  it "no orphan entry files outside sections" do
    entries = Dir.children(knowledge_dir).reject { |e| e.start_with?(".") || File.directory?(File.join(knowledge_dir, e)) }
    known_root = %w[project.md]
    orphans = entries - known_root
    expect(orphans).to be_empty,
                       "entries outside sections: #{orphans.join(", ")}"
  end

  it "has the core loop sections" do
    sections = Dir.children(knowledge_dir).select { |e| File.directory?(File.join(knowledge_dir, e)) }
    expect(sections).to include("goals", "rules", "architecture", "decisions", "patterns", "runbooks", "specs")
  end

  it "each section has content" do
    Dir.children(knowledge_dir).select { |e| File.directory?(File.join(knowledge_dir, e)) }.each do |section|
      files = Dir[File.join(knowledge_dir, section, "*.md")]
      expect(files).not_to be_empty, "section #{section} has no markdown files"
    end
  end
end
