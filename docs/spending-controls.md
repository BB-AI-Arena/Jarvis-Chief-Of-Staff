# Director spending controls

Owner-selected allowance: $10 USD per director per America/Chicago calendar day. Enforcement applies to newly launched native director requests in this source build; it does not retroactively control installed older builds, other apps, direct Python scripts, cloud voice, or already-running jobs.

`SpendBudget` reserves a conservative upper bound before each billed native Claude/Grok request. It charges the full supported context at the highest standard input rate, plus the explicit output maximum. Reservations persist in private Application Support/Jarvis/Budgets/daily.json, use an interprocess file lock, and settle at conservative standard token rates only after successful responses carrying valid usage. Errors, cancellation and missing usage retain the full reservation; replayed or prior-day responses cannot release another request’s allowance. The reservation prevents concurrent requests from oversubscribing the allowance; settlement lets later writing/review rounds use the released funds. Supported output bounds extend to 32,000 tokens. This can still stop earlier than actual billing. TokenMeter remains the measured usage view, not a dollar bill. Day rollover is based on request authorization time.

Supported models: Claude Haiku 5.5 (Jarvis routing), Sonnet 5.5 and Opus 5.5; Grok 4.7 and grok-4.20-0309-non-reasoning. Unknown models, stale rates after November 30, malformed state, failed persistence, unbounded output, server-side search and implicit server history are refused. Grok's existing fallback can answer without live web search and must disclose that limitation. Local Ollama planning remains available.

Cursor has no verified per-run maximum charge in the inspected API contract. New Cursor agents, Operations workers, native film worker launches and paid Grok video renders therefore stop before launch. This is a deliberate restriction, not a claim that polling or cancelling a remote run guarantees its final bill. A local GPU film pipeline can still invoke paid models, so it is not assumed free. Restoring those paths requires provider-enforced caps or complete bounded accounting across every subprocess and fallback. Existing external jobs are not cancelled by this source update.

Rate references checked November 12, 2026:
- https://platform.claude.com/docs/en/about-claude/pricing
- https://docs.x.ai/developers/pricing
- https://prod.cursor.com/docs/cloud-agent/api/endpoints

These controls use published standard API rates and exclude taxes and account-specific surcharges. They are not a provider billing statement or an account-wide cap.

Production motion is owner-restricted to local models on DARK/RTX 4090. Retained cloud-video adapters are not authorized fallbacks. A future bounded film broker must preserve that restriction; frontier models may plan/review only within their separately enforced allowance.
