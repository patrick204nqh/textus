Textus::Protocol::Session::Bridge = Data.define(:container, :gate) do
  def store         = container.store
  def manifest      = container.manifest
  def schemas       = container.schemas
  def layout        = container.layout
  def workflows     = container.workflows
  def root          = container.root
  def ttl_evaluator = container.ttl_evaluator

  def dispatch(...) = gate.dispatch(...)
end
