# Documentation Structure

This file records the documentation structure decision for this repository and future similar starter-kit repositories.

## Decision

Use a hybrid documentation structure:

- top-level docs hold project-wide rules, user entrypoints and AI/development decisions;
- layer-specific folders own their own README files;
- detailed operational commands live next to the files/scripts they describe.

Current structure:

| File | Role |
|---|---|
| `README.md` | Short entrypoint and artifact map |
| `docs/USER_GUIDE.md` | Full human-facing usage and operation guide |
| `docs/STARTER_KIT_AI_RULES.md` | Generic AI checklist/rules for starter-kit repositories |
| `docs/SUPABASE_AI_GUIDE.md` | Supabase-specific AI/development guide |
| `docs/DOCUMENTATION_STRUCTURE.md` | Records this documentation policy |
| `scripts/README.md` | Script-specific usage, inputs, outputs and safety notes |
| `dokploy/README.md` | Dokploy template generation and import details |
| `tests/README.md` | Test layer entrypoint |
| `tests/runtime/README.md` | Vitest runtime test usage and coverage |

## Why

The first cleanup consolidated too much into large top-level docs. That reduced file count but made unrelated updates touch the same documents.

The current structure keeps global decisions centralized while letting each technical layer own its local operating details.

The new structure separates by audience and stability:

- users get one guide that points to layer READMEs;
- AI agents get one generic reusable rulebook;
- this repository gets one app-specific AI guide;
- scripts, Dokploy and runtime tests own their own local docs;
- the structure itself is documented so future edits do not reintroduce uncontrolled doc sprawl.

## Rules for future docs

- Do not add a new docs file for every topic by default.
- Add a folder README when the folder has enough behavior that central docs would drift or become noisy.
- If a new docs file is added, update this file and explain why.
- Keep generic starter-kit rules out of the app-specific guide.
- Keep app-specific operational details out of the generic rulebook.
- Keep layer-specific commands in the layer README.
- Keep `README.md` short; detailed usage belongs in `docs/USER_GUIDE.md`.
