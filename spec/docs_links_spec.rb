# spec/docs_links_spec.rb
require "pathname"

DOCS_REPO_ROOT = Pathname.new(File.expand_path("..", __dir__))

RSpec.describe "documentation links" do
  ignored = `git -C #{DOCS_REPO_ROOT} ls-files --others --ignored --exclude-standard`.split("\n").to_set do |rel|
    (DOCS_REPO_ROOT + rel).to_s
  end

  md_files = Dir[File.join(DOCS_REPO_ROOT, "**/*.md")].reject do |p|
    p.include?("/vendor/") || p.include?("/node_modules/") || p.include?("/.git/") || ignored.include?(p)
  end

  md_files.each do |file|
    # Strip code so we don't scan ]( inside examples. Fenced blocks go first
    # (whole-block), THEN inline spans — and inline matching must NOT cross
    # newlines (`[^`\n]`), or backtick-dense files pair backticks across lines
    # and silently swallow real links between them.
    content = File.read(file)
                  .gsub(/^[ \t]*```.*?^[ \t]*```/m, "") # fenced code blocks
                  .gsub(/`[^`\n]*`/, "``")              # inline code spans (single line)
    targets = content.scan(/\]\(([^)]+)\)/).flatten
    rel = Pathname.new(file).relative_path_from(DOCS_REPO_ROOT).to_s # rubocop:disable RSpec/LeakyLocalVariable

    targets.each do |target|
      next if target.start_with?("http://", "https://", "mailto:", "#")

      path_part = target.split("#").first # rubocop:disable RSpec/LeakyLocalVariable
      next if path_part.nil? || path_part.empty?

      it "#{rel}: link resolves -> #{target}" do
        resolved = (Pathname.new(file).dirname + path_part).cleanpath
        expect(resolved.exist?).to(
          be(true),
          "broken link `#{target}` in #{rel}",
        )
      end
    end
  end
end
