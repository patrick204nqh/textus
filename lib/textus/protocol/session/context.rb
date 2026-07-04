Textus::Protocol::Session::Context = Data.define(:role, :correlation_id, :dry_run, :cursor, :contract_etag, :propose_lane) do
  def call
    Textus::Value::Call.build(role:, correlation_id:)
  end
end
