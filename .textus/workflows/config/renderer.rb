Textus.workflow "render" do
  match "artifacts.render.**"
  step(:render) { |_, _| {} }
end
