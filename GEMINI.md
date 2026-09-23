<!-- Generated from workspace-wiki/meta/routers.yml by scripts/router.py. Do not edit by hand. -->

# Agent Router: STTBar

Router for STTBar, a macOS menu bar app for dictation with Whisper. The
profile lives in the vault, repo notes in `docs/agent-notes.md`.

## Always Read In This Order

1. `../workspace-wiki/agents/README.md`: the shared reading chain of the ProjectMakers vault
2. `../workspace-wiki/projects/sttbar/README.md`: this project's page in the vault
3. [README.md](README.md): features, install and configuration
4. [docs/agent-notes.md](docs/agent-notes.md): repo notes for agents

If `../workspace-wiki` is missing, clone the vault there first. Without it the shared
half of the rules is missing. The vault is private, its clone URL is in the
router of every private ProjectMakers repository.

## Secrets

Never put a secret value into a page or a commit. Rules for every project:
`../workspace-wiki/agents/environment.md`, section 6. Cross-project keys:
`../workspace-wiki/infrastructure/secrets.md`.

## Rules

- Releases come from semantic-release on `master`. Work lands on `develop`. Never tag or edit `CHANGELOG.md` by hand.
