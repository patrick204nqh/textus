require "stringio"

# The StringIO-triple + `Textus::Surfaces::CLI.run` invocation that every CLI spec
# re-creates. Include it and call `run(argv)`; read `stdout`/`stderr` or the
# parsed `json_out`. Pass extra kwargs (e.g. `cwd:`) straight through:
#
#   include_context "cli invocation"
#   it "emits rows" do
#     expect(run(["audit"], cwd: tmp)).to eq(0)
#     expect(json_out["verb"]).to eq("audit")
#   end
RSpec.shared_context "cli invocation" do
  let(:stdin)  { StringIO.new }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  # `cwd` defaults to the store fixture's `tmp` (the dominant pattern); pass
  # `cwd:` to override, or any other CLI.run kwarg through `**opts`.
  def run(argv, cwd: tmp, **opts)
    Textus::Surfaces::CLI.run(argv, stdin: stdin, stdout: stdout, stderr: stderr, cwd: cwd, **opts)
  end

  def json_out = JSON.parse(stdout.string)
end
