# Research retry recovery

The previous iOS status handler collapsed HTTP errors and malformed responses
into a generic connection error. It retained the saved job ID, so Retry checked
the same job even when the bridge returned `404 job_not_found`. Failed and
interrupted jobs also remained selected for status-only retries indefinitely.

The bridge stores job stages under `.local/trip-pipeline/jobs/<uuid>`. Render's
free service uses temporary filesystem storage. A redeploy can remove these
files while iOS retains the job ID in its local trip storage. Rebuilding or
restarting the app does not clear that stored reference.

Recovery now clears only the matching job reference on a job-status 404 or a
terminal failed/interrupted response. The saved plan, brief, edits, map
coordinates and other user fields remain intact. The screen offers **Ξεκίνα νέα
έρευνα**; it does not automatically dispatch another paid research request.
Temporary status failures keep the job and retry read-only GET requests up to
four times with 2/4/8-second pauses. Research POST requests have no application
retry loop. Missing jobs and invalid responses are not retried automatically.

Preflight reports `research_ready` and `configuration_issues` with setting names
only. It checks explicit paid-call authorization, positive finite budget/rate
settings, currency, endpoints, API-key presence and model deployment. It does
not initialize an SDK, validate remote credentials or make a provider call.
Existing-job reads remain available even when new research is disabled. Provider
configuration, exhausted budget, storage and generic execution failures have
distinct safe error codes. The iOS support disclosure shows stage/status codes
and setting names, without credentials or job capabilities.

`render.yaml` declares the required budget settings without enabling paid calls
or supplying invented rates. Existing Render services need the intended values
in their Environment settings; pushing code alone does not supply them.

On 2026-11-03, a read-only live preflight returned HTTP 200 with build commit
`03b293c1250cd657edcd5cd374b797cfcc21114e`, API version 3 and research contract
version 4. The user's deploy was current. That old preflight does not expose
configuration readiness, and the screenshot's exact job response was unavailable.
The retry defect is verified in code and synthetic regressions; it is not proof
of the exact live job error. No paid research was executed during verification.

This patch handles job loss; durable cloud job storage across deployments is
still outstanding. Full Xcode/Simulator validation was unavailable in the
execution environment. Native transport/storage harnesses and an iOS SDK
typecheck validate the modified code without a simulator.
