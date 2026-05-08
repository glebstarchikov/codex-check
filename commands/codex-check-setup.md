---
description: Analyze the current repo and propose a "## Codex Check Triggers" section for its CLAUDE.md
allowed-tools: Bash, Read, Edit, Write, Glob, Grep
---

Per-project setup for codex-check. Run once per repository to populate the trigger surfaces that codex-check should auto-fire on.

## Step 1: Locate repo root

```bash
git rev-parse --show-toplevel
```

If this fails, ask the user to run the command from inside a git repository.

## Step 2: Gather signal

Read the following (each is best-effort — file might not exist):

- `CLAUDE.md` at repo root — existing conventions, invariants, "must not regress" language
- `README.md` at repo root — project description, stack
- Top-level directory structure (`ls -la` output, focusing on `db/`, `auth/`, `server/`, `api/`, `migrations/`, etc.)
- `package.json` (or `pyproject.toml` / `Cargo.toml` / `go.mod`) — dependencies that hint at high-risk areas
- Recent commit subjects: `git log --oneline -20`

## Step 3: Identify high-risk surfaces

Look for files/directories matching:

- **Database / persistence:** `db/`, `migrations/`, `prisma/`, `schema.{ts,sql,py,rb}`, ORM tenant primitives
- **Auth / sessions:** `auth/`, `session/`, anything with password hashing, OAuth flows, JWT signing
- **Realtime / streaming:** WebSocket handlers, SSE endpoints, message brokers
- **Webhooks / payments:** webhook handlers, Stripe/payment integration
- **Env / secrets:** `env.{ts,py}`, `config/`, secret loaders
- **Security-sensitive code:** CSRF, CORS, sanitization, encryption helpers
- **Infrastructure:** Dockerfile, deploy scripts, fly.toml, vercel.json, k8s manifests if they affect runtime
- **Anything CLAUDE.md explicitly flags:** existing CLAUDE.md sections labelled "invariant," "must not regress," "load-bearing," "do not regress"

## Step 4: Draft the triggers section

Construct a `## Codex Check Triggers` markdown section. For each surface, give a file path or glob and a one-line rationale (the *why*, not the *what*). Example:

````markdown
## Codex Check Triggers

Fire `/codex-check` (or auto-invoke via the codex-check skill) before
reporting completion when the diff touches any of:

- `db/schema.ts`, `db/migrations/` — schema or migration changes can break tenant isolation silently
- `db/tenant.ts`, files importing `tenantDb`/`adminDb` — invariant: app code must not bypass the tenant primitive
- `server/routes/_ws.ts` — websocket lifecycle; race conditions cause silent session drops
- `server/utils/auth/*` — auth changes have the largest blast radius

**Why these surfaces:** <one-paragraph rationale tying back to the project's specific risks>.
````

The rationale paragraph is important — it explains why this list, not just what's on it.

## Step 5: Show + approve

Show the proposed section to the user. Ask whether to:

1. Write it as-is to CLAUDE.md
2. Edit before writing (let the user dictate changes)
3. Skip — they'll write it manually later

If the user approves, append the section to existing CLAUDE.md (or create the file with just this section if it doesn't exist).

## Step 6: Idempotency

If `## Codex Check Triggers` already exists in CLAUDE.md, do **not** overwrite. Instead:

1. Read the existing section
2. Compare with what you would have proposed
3. Show the diff to the user
4. Ask whether to merge / replace / skip

Running the command twice with no codebase changes should produce no diff and exit cleanly.

## Step 7: Confirm

Print one line confirming what was done: "Wrote `## Codex Check Triggers` section to CLAUDE.md (8 surfaces)." or "No changes — section already present and current."
