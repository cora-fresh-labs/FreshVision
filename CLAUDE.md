# Operating rules for coding agents

These apply to every coding agent working in this repo. Each one prevented (or would have
prevented) a real, expensive failure. Follow them by default; if a rule blocks the task, stop and
flag it rather than working around it.

## Writing
- Never use em dashes anywhere: code comments, commit messages, UI copy, reports, chat.
  Restructure with a comma, colon, period, or parentheses. En dashes in numeric ranges are fine.

## Real-or-gap (data honesty)
- Never present fabricated, demo, or indicative data as if it were live. If real data is
  unavailable, show an honest gap labeled with the reason and an as-of date. A non-US commodity
  must never display US prices as if local. One fake "live" number destroys trust in all of them.

## Verify the way production verifies
- "Done" means proven through the same path the user or prod uses: run the real build (not just a
  hook or typecheck), load the actual rendered page, screenshot prod (not localhost). Show the
  proof. Never claim done on a passing typecheck or a localhost screenshot alone.

## Deploy discipline
- No deploy without an explicit go. Confirm which project before deploying (they map to different
  hosts; see the /deploy skill).
- Shared git trees: commit with explicit pathspecs (never `git add .`), land on main via the
  worktree recipe, never force-push over another agent's commit. Reconcile first.

## Secrets and irreversible actions
- Never generate, echo, or print a secret value, in chat or on a command line (shell history is
  not safe). Pull secrets from the environment at runtime (`vercel env pull`, `doppler run`).
  Clint generates and sets secret values; agents read them and report pass/fail only.
- Never deploy, rotate a credential, send a message, or take any irreversible or outward action
  without explicit say-so.

## Bounded, self-terminating loops
- Every wait, poll, or background task gets a timeout and an exit condition. Put `--max-time` on
  every prod curl. Never block indefinitely. If the expected state has not appeared after a
  sensible bound, stop and report the blocker by name rather than waiting.

## Port, don't invent
- Prefer extending existing code over rebuilding. The pattern is usually "this exists, it's just
  not organized right." Read the existing implementation first and build on it. Do not stand up a
  parallel second system for something that already has one.

## One owner, contract first
- If more than one agent will touch the same surface, the shared contract or interface is written
  and locked first, and exactly one agent owns each surface. Never run two agents on the same files.

## Propose before big builds
- For any non-trivial change, read the relevant code, then propose the plan and the irreversible
  decisions (schema, data shape, auth model) and get sign-off before writing. Irreversible
  decisions are cheap to change on paper and brutal to change after they ship.

## Definition of done
- State it in user terms before starting: "done when Clint can [do X] and see [Y]." The loop
  terminates on that, verified, not on "I wrote the code."
