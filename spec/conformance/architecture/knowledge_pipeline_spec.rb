RSpec.describe "Knowledge pipeline conformance" do
  let(:known_sections) do
    %w[intent constraint evidence judgment execution feedback]
  end

  def loop_dir
    File.expand_path("../../../.textus/data/knowledge/loop", __dir__)
  end

  it "every loop section is a known section" do
    sections = Dir.children(loop_dir).select { |e| File.directory?(File.join(loop_dir, e)) }
    unknown = sections - known_sections
    expect(unknown).to be_empty,
                       "unknown loop sections: #{unknown.join(", ")}"
  end

  it "has the core loop sections" do
    sections = Dir.children(loop_dir).select { |e| File.directory?(File.join(loop_dir, e)) }
    expect(sections).to include("intent", "constraint", "evidence", "judgment", "execution", "feedback")
  end

  it "each section has content" do
    Dir.children(loop_dir).select { |e| File.directory?(File.join(loop_dir, e)) }.each do |section|
      files = Dir[File.join(loop_dir, section, "**", "*.md")]
      expect(files).not_to be_empty, "section #{section} has no markdown files"
    end
  end

  it "recent decisions (ADR-0119+) reference judgment engineering (pipeline: judgment → evidence)" do
    decisions = Dir[File.join(loop_dir, "evidence", "0*.md")].grep(/01(19|2[0-5])/)
    offenders = decisions.reject do |f|
      File.read(f).match?(%r{knowledge\.loop\.judgment\.engineering\.|\.textus/data/knowledge/loop/judgment/engineering})
    end
    expect(offenders).to be_empty,
                         "decisions after ADR-0119 missing architecture reference:\n#{offenders.map do |f|
                           "  #{f.sub(loop_dir, "knowledge.loop")}"
                         end.join("\n")}"
  end

  it "judgment engineering files reference decisions (pipeline: evidence → judgment)" do
    patterns = Dir[File.join(loop_dir, "judgment", "engineering", "*.md")]
    offenders = patterns.reject { |f| File.read(f).match?(/knowledge\.loop\.evidence\.|ADR-\d+|knowledge\.loop\.judgment\.engineering\./) }
    expect(offenders).to be_empty,
                         "patterns missing decision reference:\n#{offenders.map do |f|
                           "  #{f.sub(loop_dir, "knowledge.loop")}"
                         end.join("\n")}"
  end

  it "runbooks reference patterns (pipeline: patterns → runbooks)" do
    runbooks = Dir[File.join(loop_dir, "execution", "*.md")]
    offenders = runbooks.reject { |f| File.read(f).match?(/knowledge\.loop\.(patterns|judgment\.engineering)\./) }
    expect(offenders).to be_empty,
                         "runbooks missing pattern reference:\n#{offenders.map { |f| "  #{f.sub(loop_dir, "knowledge.loop")}" }.join("\n")}"
  end
end
