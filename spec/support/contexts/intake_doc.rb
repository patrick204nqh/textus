# Wraps the `intake_store` preset + the `resolve_intake` hook heredoc that ~15
# specs re-author by hand. Include alongside "textus_store_fixture" (which
# provides `root`); override the knobs via `let` where a spec needs them:
#
#   include_context "textus_store_fixture"
#   include_context "intake doc"
#   let(:intake_ttl) { "1s" }              # default "1h"
#
# Exposes `store` (an intake-wired Store) so the host can call straight into it.
RSpec.shared_context "intake doc" do
  let(:intake_ttl)       { "1h" }
  let(:intake_kind_zone) { "machine" }
  let(:intake_body) do
    <<~RUBY
      Textus.hook do |reg|
        reg.on(:resolve_intake, :test_intake) { |caps:, config:, args:| { _meta: { "name" => "doc" }, body: "fresh" } }
      end
    RUBY
  end
  let(:store) do
    intake_store(
      root,
      intake_body: intake_body,
      ttl: intake_ttl,
      kind_zone: intake_kind_zone,
    )
  end
end
