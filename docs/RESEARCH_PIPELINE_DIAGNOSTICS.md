# Empty research and troubleshooting

An initial research failure previously stopped further paid dispatch, skipped
selected-place checks, then composed and delivered an empty `partial` result.
The app reported composition and saving as completed, even with zero places.
The planner now marks zero-place results `failed`; the bridge delivers an error
with the retained diagnostics. No empty result replaces an existing iOS plan.
Composition is certified only when it produces scheduled stops. Useful partial
results with actual places are still retained and can be opened.

Every job has a separate support ID, distinct from its private job capability.
Status diagnostics retain up to 100 events: stage starts/completions, failures,
skipped phases, elapsed time, and counts of citations, sources and places. A
failure identifies its task and stage (`web_conversation`, `web_response`, or
`luna_normalization`), error category, HTTP status when available, and selected
safe parameter/token-limit details. Provider messages and bodies are not copied
to diagnostics. Validator paths are accepted only from fixed local prefixes.

The production bridge logs structured INFO events using the support ID. These
events contain no brief, preferences, credentials, request bodies, raw source
text, or private job ID. Preflight still exposes no other job's result or
diagnostics. Detailed status access still requires that job's capability.

The app shows a support disclosure for failures and saved partial results; the
plan overview includes it too. Copy the generated support text to investigate
the task, stage, HTTP code and output counts. Old saved documents can show their
existing `failed_stages`, but cannot gain HTTP codes lost by the old provider.

Use the support ID to locate `trippy.research` events in Render runtime logs.
The provider's raw responses/uncertain-spend receipts stay in the restricted
server storage. Inspect the retained receipt before authorizing another paid
dispatch; these changes do not introduce provider retries or release charges.

On 2026-11-03, live preflight for the screenshot's deployed build
`057074df3ecba03470bb4361ac929f5d5ed7934f` reported research ready with no missing
configuration. The mobile job capability and Render log tools were unavailable,
so the exact live provider error was not observed. The empty-result defect and
diagnostic propagation are verified using injected failures without paid APIs.

Durable server job storage and production cost reconciliation remain separate
work. Diagnostics cannot restore files already removed by a redeploy.
