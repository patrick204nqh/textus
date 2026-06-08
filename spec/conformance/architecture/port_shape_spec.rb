require "spec_helper"

# ADR 0109 (supersedes ADR 0108's two-shape allowance) — ports are the only IO
# doorway and must all share the same single shape: an instantiable class. The
# earlier ADR 0108 permitted either a stateless module or an instantiable class;
# ADR 0109 unifies to one shape so every port is constructed, injected, and
# tested the same way. This guard enforces that every port in lib/textus/ports/
# is declared as a class (not a bare module) and carries a doc comment.
RSpec.describe "port shape convention (ADR 0109)" do
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

  it "every port is an instantiable class (ADR 0109 single shape)" do
    module_ports = port_files.reject do |f|
      idx, lines = port_declaration(f)
      next true unless idx  # no class/module declaration: reported by the structural test above

      lines[idx] =~ /^\s+class\s/
    end
    expect(module_ports).to be_empty,
                            "ADR 0109: every port is an instantiable class; these are still modules:\n  " \
                            "#{module_ports.map { |f| f.sub(%r{.*/lib/}, "lib/") }.join("\n  ")}"
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
                            "these ports lack a doc comment on their declaration (ADR 0108/0109 — a port " \
                            "must say what it is):\n  " \
                            "#{undocumented.map { |f| f.sub(%r{.*/lib/}, "lib/") }.join("\n  ")}"
  end
end
