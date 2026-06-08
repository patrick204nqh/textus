module Textus
  class Manifest
    module Schema
      # The closed coordination vocabulary (ADR 0028; five in 0033; unified in
      # 0034; the quarantine + derived ZONE-KINDS folded into one `machine` kind
      # in ADR 0091). Each kind pairs with the capability that authorizes
      # originating bytes in it. ONE source of truth; the derived constants below
      # cannot drift. A BIJECTION again (0090 had two kinds → reconcile; 0091
      # collapses them, so kind ↔ capability is 1:1).
      module Vocabulary
        LANES = {
          "canon" => "author",
          "workspace" => "keep",
          "machine" => "reconcile",
          "queue" => "propose",
        }.freeze

        ZONE_KINDS         = LANES.keys.freeze
        CAPABILITIES       = LANES.values.uniq.freeze
        KIND_REQUIRES_VERB = LANES
      end
    end
  end
end
