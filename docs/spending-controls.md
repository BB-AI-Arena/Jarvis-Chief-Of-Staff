# Director spending controls

Owner-selected allowance: $15 USD for Creative and $10 USD for each other director per America/Chicago calendar day. Existing spending and unsettled holds count toward these limits. Enforcement applies to newly launched native director requests in this source build; it does not retroactively control installed older builds, other apps, unrelated Python scripts, cloud voice, or already-running jobs. The included film worker now requires the native budget broker for its paid provider calls, including after supervisor restarts.

`SpendBudget` reserves a conservative upper bound before each billed native Claude/Grok request. It charges the full supported context at the highest standard input rate, plus the explicit output maximum. Reservations persist in private Application Support/Jarvis/Budgets/daily.json, use an interprocess file lock, and settle at conservative standard token rates only after successful responses carrying valid usage. Errors, cancellation and missing usage retain the full reservation; replayed or prior-day responses cannot release another request’s allowance. The reservation prevents concurrent requests from oversubscribing the allowance; settlement lets later writing/review rounds use the released funds. Supported output bounds extend to 32,000 tokens. This can still stop earlier than actual billing. TokenMeter remains the measured usage view, not a dollar bill. Day rollover is based on request authorization time.

Supported models: Claude Haiku 5.5 (Jarvis routing), Sonnet 5.5 and Opus 5.5; Grok 4.7 and grok-4.20-0309-non-reasoning. Unknown models, stale rates after November 30, malformed state, failed persistence, unbounded output, server-side search and implicit server history are refused. Grok's existing fallback can answer without live web search and must disclose that limitation. Local Ollama planning remains available.

Cursor has no verified per-run maximum charge in the inspected API contract. New Cursor agents and Operations workers therefore stop before launch. Cloud video rendering is hard-disabled independently of budget. This is a deliberate restriction, not a claim that polling or cancelling a remote run guarantees its final bill. A local GPU film pipeline can still invoke paid models, so it is not assumed free. Restoring unbounded agent paths requires provider-enforced caps or complete bounded accounting across every subprocess and fallback. The included film worker routes paid planning/review and supported still-image repairs through an allowlisted native broker, always charged to Creative; missing broker, unsupported operation or insufficient allowance fails closed. Fixed-price still repairs reserve the full supported charge without refund. Existing external jobs are not cancelled by this source update.

Rate references checked November 12, 2026:
- https://platform.claude.com/docs/en/about-claude/pricing
- https://docs.x.ai/developers/pricing
- https://prod.cursor.com/docs/cloud-agent/api/endpoints

These controls use published standard API rates and exclude taxes and account-specific surcharges. They are not a provider billing statement or an account-wide cap.

Production motion is owner-restricted to local models on DARK/RTX 4090. Retained cloud-video adapters are not authorized fallbacks. The film broker preserves that restriction and refuses video endpoints; frontier models may plan/review only within their separately enforced allowance.

Film production defaults to local DARK planning and frame review through Ollama, with local rendering. Local-only jobs reject external provider requests and redirects; they do not need the paid film broker. Sonnet conversation remains separate.
