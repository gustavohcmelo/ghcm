# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

GHCM (Gated Hub CLI Manager) is a **bash-only orchestrator** that runs four LLM CLIs in four tmux panes — `planner`, `developer`, `reviewer`, `git-manager` — with manual approval gates between stages. There is no application code: everything is shell scripts, prompt files, and templates. The repo is the tool itself, installed via symlink at `~/ghcm`.

User-facing prose (README, agent prompts, output messages) is in **pt-BR**. Code identifiers (paths, branches, commit messages, variable names) are in **English**. Preserve this split when editing.

## Common commands

```bash
# Install (creates ~/.local/bin/ghcm symlink, validates deps)
./install.sh

# Lint locally before pushing (CI runs the same)
shellcheck ghcm start.sh install.sh config.example.sh
shfmt -d -i 2 -ci ghcm start.sh install.sh config.example.sh

# Run / debug the orchestrator
ghcm start [project_dir]   # spawns tmux session 'agents-<slug>'
ghcm status [slug]         # inspect plans/reviews queues
ghcm logs                  # browse ~/ghcm/logs/ (timestamped init logs)
ghcm clean <slug>          # nuke state/<slug>/ (session must be stopped first)
```

There are no unit tests. Validation is end-to-end: `ghcm start` in a real git project, walk through the planner → developer → reviewer → git-manager pipeline, confirm a PR opens via `gh`.

## Architecture: where state lives

Two distinct trees, kept separate on purpose:

- **`~/ghcm/`** — this repo. Code (`ghcm`, `start.sh`), agent prompts (`agents/<role>/`), config (`config.sh`), templates.
- **`~/ghcm/state/<slug>/`** — runtime, gitignored, one subtree per project. `plans/{pending,done}/`, `reviews/{pending,done/{approved,rejected,shipped}}/`, `exports/`, `.project-path`.

The user's project repo is **never polluted** with plans or reviews. The slug = `basename(project_dir)`.

## Architecture: how agents find their project

Critical invariant: agents derive the active project from the **tmux session name** (`tmux display-message -p '#S'`, strip `agents-` prefix), **not** from `~/ghcm/current-project.txt`. The global file exists only as a fallback for compatibility — `Ctrl-b s` (tmux's native session switch) must remain safe, which means each pane must read the slug fresh from its own session each time it acts.

When editing agent prompts (`agents/<role>/CLAUDE.md|AGENTS.md`), keep the slug-resolution snippet at the top intact. The reviewer uses `AGENTS.md` (codex convention); the others use `CLAUDE.md` (claude convention) — swapping a role's CLI may require renaming this file.

## Architecture: the gated pipeline

```
planner (text only) ──user approves──▶ state/<slug>/plans/pending/
developer ──executes plan──▶ state/<slug>/plans/done/  +  reviews/pending/
reviewer ──reads diff──▶ reviews/done/{approved,rejected}/
                            │
                approved ──▶ git-manager ──▶ branch + commit + push + gh pr create ──▶ reviews/done/shipped/
                rejected ──▶ developer creates -v2/-v3 entry in reviews/pending/
```

Re-revisions are versioned files (`<base>-v2.md`, `-v3.md`), not new plans — the developer addresses reviewer notes without round-tripping through the planner.

## Frontmatter contract

Every `.md` file in `state/<slug>/plans/` and `state/<slug>/reviews/` **must** start with YAML frontmatter. Required keys:

- Plans: `id`, `created_at`, `project_slug`, `kind: plan`, `status`, `version`, `type` (drives branch prefix `feat/`/`fix/`/`chore/`/`docs/`/`refactor/`/`test/`).
- Reviews: same plus `plan_ref`, `previous_review_ref` (null on first review).

`ghcm status` warns about legacy files missing frontmatter. The reviewer/git-manager update `status:` in-place when moving files between dirs (`pending → approved → shipped`, etc.).

## start.sh: pane wiring details that matter

- Pane IDs (`%X`) are captured at creation and reused for `set -p` and `send-keys` — do not assume positional order, layouts get re-tiled.
- Per-pane `@role_label` (user-defined option) holds the colored title. `pane_title` is unreliable because `claude`/`codex` overwrite it via escape sequences.
- `wait_for_ready` polls `tmux capture-pane` for CLI-specific markers (see `ready_marker_for`). Adding a new CLI requires adding a marker there.
- `monitor-silence 5` is set **after** CLIs boot, otherwise the boot silence triggers it.
- `wait_for_ready` is followed by `|| true` because under `set -e`, a timeout would abort before `exec tmux attach` and leave the user with a detached session and no feedback. Preserve this.

## Editing agent prompts

Each role's behavior is defined entirely by its prompt file. Treat these as production code:

- Keep the "projeto ativo" block (slug-from-tmux) at the top.
- Keep the "[STATUS: idle — aguardando próxima instrução]" sign-off rule — agents are async and the user reads pane status from this line.
- Frontmatter templates in `developer`/`planner` prompts must stay in lock-step with what `ghcm status` validates and what `git-manager` reads.

## CLI requirements

The four roles are configured via `~/ghcm/config.sh` (initialized from `config.example.sh` on first run). CLIs that need tool use (developer, git-manager, reviewer) must be `claude`, `codex`, or `gemini`. `ollama` works only for planner (text-only, no tool use).
