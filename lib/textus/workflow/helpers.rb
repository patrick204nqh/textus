require "net/http"
require "json"
require "erb"

module Textus
  module Workflow
    module Helpers
      def fetch_json(url, headers: {})
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 5
        http.read_timeout = 30

        request = Net::HTTP::Get.new(uri)
        headers.each { |k, v| request[k] = v }
        request["Accept"] ||= "application/json"

        response = http.request(request)
        raise "HTTP #{response.code} for #{url}" unless response.is_a?(Net::HTTPOK)

        JSON.parse(response.body)
      end

      def render_template(name, data)
        path = @container.layout.template_path(name)
        raise "template not found: #{name}" unless File.exist?(path)

        template = File.read(path)
        ctx = Textus::Produce::Render::Context.new(
          container: @container, call: @call,
          key: @ctx&.key, entry: @ctx&.entry,
        )
        renderer = Textus::Produce::Render.new(template, ctx)
        renderer.bytes_for(data)
      end

      def merge_hashes(*hashes)
        hashes.reduce({}) { |acc, h| deep_merge(acc, h) }
      end

      def pluck(source, *keys)
        source.select { |k, _| keys.include?(k) }
      end

      private

      def deep_merge(a, b)
        a.merge(b) do |_key, old_val, new_val|
          if old_val.is_a?(Hash) && new_val.is_a?(Hash)
            deep_merge(old_val, new_val)
          else
            new_val
          end
        end
      end
    end
  end
end
