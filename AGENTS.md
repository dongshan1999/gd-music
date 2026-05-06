# AGENTS.md

## File Viewing
- When reading Godot text files that may contain Chinese or emoji, prefer `tools/show_utf8.ps1`.
- Applies to: `*.tscn`, `*.gd`, `*.csv`, `*.translation`, and `project.godot`.
- Avoid direct `Get-Content` when the goal is to inspect user-facing Chinese text.
- Preferred commands:
  - `.\tools\show_utf8.ps1 <path>`
  - `.\tools\show_utf8.ps1 <path> -Contains 'text =' -LineNumbers`
  - `.\tools\show_utf8.ps1 <path> -Start 1 -End 120`

## Fallback
- If `show_utf8.ps1` is unavailable, use `tools/show_utf8.py` with `PYTHONIOENCODING=utf-8`.
- Avoid assuming terminal output means the file encoding is broken. Verify with the UTF-8 viewer first.

## Godot Workflow
- Prefer Godot MCP for running the project, reading debug output, and scene-level operations when those tools are available.
- Use shell commands mainly for repository inspection, text search, and file-level edits.

## Scene Refactors
- When splitting large `.tscn` files into sub-scenes, preserve node names that are referenced by `%NodeName` in scripts unless the scripts are updated in the same change.
