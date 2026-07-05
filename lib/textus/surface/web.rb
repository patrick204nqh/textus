require "sinatra/base"
require "json"

module Textus
  module Surface
    class Web < Sinatra::Base
      set :textus_session, nil
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

      post "/api/:verb" do
        content_type :json
        session = settings.textus_session.with_role(request.env["HTTP_X_TEXTUS_ROLE"] || "agent")
        body = begin
          JSON.parse(request.body.read)
        rescue StandardError
          {}
        end
        result = Textus::Surface::Dispatch.call(session, params[:verb], body)
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
