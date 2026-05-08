---
description: Run a 3-axis Codex review (bugs / intent / invariant fit) on the current diff via openai/codex-plugin-cc
allowed-tools: Bash, Read, Edit
---

Execute the codex-check flow defined in the codex-check skill:

1. Read the project's CLAUDE.md (if present) and extract its `## Codex Check Triggers` section.
2. Summarize the user's stated intent for this session in 1–3 sentences.
3. Build the focus text covering three review axes (BUGS / INTENT MATCH / INVARIANT FIT) per the skill instructions.
4. Pass user-provided arguments through:
   - If the invocation includes `--base <ref>`, forward it to `/codex:adversarial-review --base <ref>`.
   - If the invocation includes `--background`, forward it.
   - Any remaining free-text after the flags is appended to the focus text *after* the 3 default axes.
5. Invoke `/codex:adversarial-review <flags> <focus text>`.
6. Triage the returned findings by severity and surface a summary per the skill's triage rules.

If `/codex:adversarial-review` fails because `openai/codex-plugin-cc` is not installed, surface the error verbatim and direct the user to:

```
/plugin marketplace add openai/codex-plugin-cc
/plugin install codex@openai-codex
/codex:setup
```

Do not try to install or repair codex yourself.
