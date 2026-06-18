# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

Textus.workflow "agentskills" do
  match "artifacts.feeds.skills"

  step :fetch do |_, _ctx|
    base = "https://agentskills.io"
    uri  = URI("#{base}/.well-known/agent-skills/index.json")
    resp = Net::HTTP.get_response(uri)
    raise Textus::Workflow::StepFailed.new(:fetch, RuntimeError.new(resp.body)) unless resp.is_a?(Net::HTTPSuccess)

    raw = JSON.parse(resp.body)
    skills = Array(raw["skills"]).map do |s|
      {
        "name" => s["name"],
        "description" => s["description"],
        "url" => "#{base}#{s["url"]}",
      }
    end

    { "content" => { "skills" => skills, "count" => skills.size } }
  end

  publish
end
