## 1. The one mental model — RPC vs pub-sub

Every event is one of two kinds.

```
   RPC                              PUB-SUB
   ───                              ───────
   • exactly 1 handler              • 0..N handlers
   • return value is USED           • return value is DISCARDED
   • raised error ABORTS the verb   • raised error LOGGED, verb continues
   • named explicitly by manifest   • triggered by lifecycle, filtered by keys:

   :resolve_intake → input to the store     :entry_put          → after any write
   :transform_rows → projection shaping     :entry_deleted      → after delete
   :validate       → doctor checks          :entry_fetched      → after fetch
                                            :build_completed    → after derived materialization
                                            :proposal_accepted  → after pending → target promotion
                                            :file_published     → after each file written to a repo path
                                            :entry_renamed      → after rename
                                            :proposal_rejected  → after proposal discard
                                            :store_loaded       → once per Store.new
                                            :fetch_started      → before intake handler runs
                                            :fetch_failed       → intake handler raised
                                            :fetch_backgrounded → timed_sync budget exceeded
```

**RPC events steer the verb's data. Pub-sub events observe the verb's outcome.** That's the whole model.

<!-- TASK 6 NOTE: framing prose salvaged from the original events.md intro (lines 6, 10), preserved here so concepts.md can fold it in. The SPEC/zones pointers from that intro are navigational and already live in the split docs' headers, so only the conceptual framing is kept: -->
> How to extend textus with Ruby hooks: when each event fires, what arguments it receives, how to define one, and how to test it. The RPC-vs-pub-sub model is the whole mental model in ~20 lines; the rest is reference you can skim on demand.
