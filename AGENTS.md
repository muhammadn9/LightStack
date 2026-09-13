# LightStack — Agent Rules

This file is the vendor-neutral convention for agentic workflows.
For build commands, code style, branch rules, and project-file rules, see [CLAUDE.md](CLAUDE.md) — that is the source of truth.

## Agentic Workflow

1. **Opus researches and plans.** Opus may dispatch subagents for research/exploration only. Opus alone decides what is required and approves the plan. No implementation begins before plan approval.
2. **User approves the plan.** The plan is presented to the repo owner for explicit go-ahead.
3. **Sonnet subagents implement.** Once approved, work is split into independent workstreams dispatched to Sonnet subagents. Subagents must not commit or push — the orchestrator builds and commits centrally. Subagents that touch overlapping files run sequentially, not in parallel.
4. **User review.** The orchestrator builds, verifies EXIT=0, and brings the repo owner in to review before anything is pushed.
5. **Push + PR.** After owner approval, push and open a PR. GitHub-side Claude review runs automatically.
6. **Back to Opus.** PR review feedback returns to Opus, which triages it and re-enters the loop at step 1 for anything needing changes.

## General Preferences

- Responses should be concise. Don't spend extra tokens. Avoid heavy technical detail unless asked.
- "Done" means the feature works completely end to end, not just that it compiles.
