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
        ctx = Textus::Protocol::Produce::Render::Context.new(
          container: @container, call: @call,
          key: @ctx&.key, entry: @ctx&.entry
        )
        renderer = Textus::Protocol::Produce::Render.new(template, ctx)
        renderer.bytes_for(data)
      end

      def merge_hashes(*hashes)
        hashes.reduce({}) { |acc, h| deep_merge(acc, h) }
      end

      def pluck(source, *keys)
        source.slice(*keys)
      end

      def check_naming(entries, pattern:, code:, fix:)
        entries.filter_map do |entry|
          key = entry_value(entry, :key)
          path = entry_value(entry, :path)
          name = path && !path.to_s.empty? ? File.basename(path.to_s) : key.to_s.split(".").last
          next if pattern.match?(name)

          {
            "code" => code,
            "level" => "warning",
            "subject" => key,
            "message" => "#{key} does not match the required naming pattern #{pattern.inspect}",
            "fix" => fix,
          }
        end
      end

      private

      def entry_value(entry, key)
        return entry.public_send(key) if !entry.is_a?(Hash) && entry.respond_to?(key)
        return entry[key] if entry.is_a?(Hash) && entry.key?(key)
        return entry[key.to_s] if entry.is_a?(Hash) && entry.key?(key.to_s)

        nil
      end

      def deep_merge(left_hash, right_hash)
        left_hash.merge(right_hash) do |_key, old_val, new_val|
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
