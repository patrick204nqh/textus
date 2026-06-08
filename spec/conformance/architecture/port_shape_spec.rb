require "spec_helper"

# ADR 0108 — ports are the only IO doorway, and they come in two sanctioned
# shapes: a stateless module (a pure function of its arguments) or an
# instantiable class (holds collaborators/config). The shapes are both fine; the
# cost the review flagged is that a newcomer had to learn each port's calling
# convention one at a time. This guard keeps that learnable: every port declares
# its type AND carries a doc comment on the declaration that says what it is.
RSpec.describe "port shape convention (ADR 0108)" do
  def port_files
    Dir[File.expand_path("../../../lib/textus/ports/**/*.rb", __dir__)]
  end

  # The port's own declaration is the deepest `class`/`module` opener whose name
  # is not a namespace (Ports/Storage). Returns [line_index, lines].
  def port_declaration(file)
    lines = File.readlines(file)
    idx = lines.rindex { |l| l =~ /^\s+(class|module)\s+(?!Ports\b|Storage\b)[A-Z]\w*/ }
    [idx, lines]
  end

  it "has port files to check (guard is wired)" do
    expect(port_files).not_to be_empty
  end

  it "every port declares a class or module under Ports" do
    undeclared = port_files.reject { |f| port_declaration(f).first }
    expect(undeclared).to be_empty,
                          "no `class`/`module` port declaration found in:\n  " \
                          "#{undeclared.map { |f| f.sub(%r{.*/lib/}, "lib/") }.join("\n  ")}"
  end

  it "every port carries a doc comment on its declaration (so its shape is learnable)" do
    undocumented = port_files.reject do |f|
      idx, lines = port_declaration(f)
      next false unless idx # handled by the declaration test above

      # Walk upward over contiguous comment lines; require at least one that is
      # real documentation (not the magic frozen_string_literal pragma).
      i = idx - 1
      i -= 1 while i >= 0 && lines[i].strip.empty?
      has_doc = false
      while i >= 0 && lines[i].strip.start_with?("#")
        has_doc = true unless lines[i].include?("frozen_string_literal")
        i -= 1
      end
      has_doc
    end

    expect(undocumented).to be_empty,
                            "these ports lack a doc comment on their declaration (ADR 0108 — a port " \
                            "must say what it is and which shape it uses):\n  " \
                            "#{undocumented.map { |f| f.sub(%r{.*/lib/}, "lib/") }.join("\n  ")}"
  end
end
