require "sinatra/base"
require "json"

module Textus
  module Surface
    class Web < Sinatra::Base
      set :textus_gate, nil
      set :textus_store, nil
      set :port, 9292
      set :bind, "0.0.0.0"
      set :server, "puma"
      set :show_exceptions, false

      get "/api/status" do
        content_type :json
        s = settings.textus_session
        boot = s.boot
        JSON.generate(protocol: boot["protocol"], lanes: boot["lanes"]&.map { |l| l["name"] }, store_root: boot["store_root"])
      end

      post "/api/:action" do
        content_type :json
        api = Textus::API.new(gate: settings.textus_gate, store: settings.textus_store)
        role = request.env["HTTP_X_TEXTUS_ROLE"] || "agent"
        session_id = request.env["HTTP_X_TEXTUS_SESSION_ID"]
        body = JSON.parse(request.body.read) rescue {}
        session = session_id ? api.resume_session(id: session_id) : api.open_session(role:)
        result = api.send(params[:action], **body, session:)
        JSON.generate(result)
      rescue Textus::Error => e
        halt status_for(e), JSON.generate(error: e.message, code: e.code.to_s)
      end

      not_found do
        content_type :json
        JSON.generate(error: "not found")
      end

      private

      def status_for(err)
        case err
        when Textus::UnknownKey, Textus::UsageError then 404
        when Textus::EtagMismatch then 409
        else 422
        end
      end
    end
  end
end
