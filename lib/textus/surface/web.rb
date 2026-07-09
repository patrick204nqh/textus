require "sinatra/base"
require "json"

module Textus
  module Surface
    class Web < Sinatra::Base
      set :textus_gate, nil
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
        adapter = Textus::Adapters::WebAdapter.new
        role = request.env["HTTP_X_TEXTUS_ROLE"] || "agent"
        body = JSON.parse(request.body.read) rescue {}
        response = adapter.call(params[:action], params: body, role: role, gate: settings.textus_gate)

        if response.success?
          JSON.generate(response.payload)
        else
          halt status_for(response.error), JSON.generate(error: response.error.message, code: response.error.code.to_s)
        end
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
