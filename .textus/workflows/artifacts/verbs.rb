Textus.workflow "verbs" do
  match "artifacts.verbs"

  step :build do |_, ctx|
    verbs = Textus::Action::VERBS.filter_map do |name, klass|
      next unless klass.respond_to?(:contract?) && klass.contract?
      spec = klass.contract
      { "name" => name.to_s, "summary" => spec.summary.to_s,
        "args" => spec.args.map { |a| a.wire.to_s }.sort }
    end
    { "content" => { "verbs" => verbs } }
  end

  publish
end
