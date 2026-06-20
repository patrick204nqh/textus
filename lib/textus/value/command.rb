module Textus
  module Value
    Command = Data.define(:verb, :params, :role) do
    def initialize(verb:, params:, role:)
      super
      params.freeze
      freeze
    end

    def [](key)    = params[key]
    def key        = params[:key]
    def pending_key = params[:pending_key]
    def dry_run    = params[:dry_run]
  end
  end
end
