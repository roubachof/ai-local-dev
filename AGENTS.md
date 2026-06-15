# AGENTS

## Default workflow for this repository
- Start high-level analysis with `README.md` and `docs/ARCHITECTURE.md`.
- Read additional files only when they are directly relevant to the user request.
- Avoid broad full-repo scans unless the user explicitly asks for exhaustive coverage.
- If a referenced file is missing, continue with existing files and mention the missing file once.

## Warp endpoint troubleshooting priorities
- First check proxy/runtime logs before broad code exploration.
- Prioritize context pressure signals in proxy logs when response quality degrades across turns.
- Keep responses concise first, then expand only if the user asks for deeper detail.
