module Textus
  module Proposal
    def self.accept(store, pending_key, as:)
      raise ProposalError.new("only human role can accept proposals; got '#{as}'") unless as == "human"

      env = store.get(pending_key)
      proposal = env["_meta"]["proposal"] or raise ProposalError.new("entry has no proposal block: #{pending_key}")
      target = proposal["target_key"] or raise ProposalError.new("proposal missing target_key")
      action = proposal["action"] || "put"

      case action
      when "put"
        target_meta = env["_meta"]["frontmatter"] || {}
        target_body = env["body"]
        store.put(target, meta: target_meta, body: target_body, as: "human")
      when "delete"
        store.delete(target, as: "human")
      else
        raise ProposalError.new("unknown action: #{action}")
      end

      store.delete(pending_key, as: "human")
      store.fire_event(:accepted, key: pending_key, target_key: target)
      { "protocol" => PROTOCOL, "accepted" => pending_key, "target_key" => target, "action" => action }
    end
  end
end
