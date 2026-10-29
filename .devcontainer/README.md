# Dev Container

Opens the project in the [Cloud Tools Container](https://hub.docker.com/r/cyclenerd/cloud-tools-container)
image, which bundles the gcloud CLI, Terraform, and other Google Cloud tooling.

Use **`Dev Containers: Reopen in Container`** in VS Code.

## Python environment

`postCreateCommand` installs [uv](https://docs.astral.sh/uv/) into `~/.local/bin`
and runs `uv sync`, which creates `/workspace/.venv` from the committed `uv.lock`.
The `python.defaultInterpreterPath` setting points the editor at that venv, so no
manual activation is needed; in a terminal, either prefix commands with `uv run`
or `source .venv/bin/activate`.

## Why `--userns=keep-id` is required

The `runArgs` entry `--userns=keep-id` is a **Podman-specific** setting. It maps
the container user's UID to your host UID.

Without it, bind-mounted files created inside the container are owned by
arbitrary host UIDs, which breaks `git` in the mounted workspace: Git's
`safe.directory` ownership check rejects the repository, so commits and other
git operations fail.

## Note on file format

`devcontainer.json` is JSONC per the
[Dev Containers schema](https://containers.dev/implementors/json_schema/)
(it sets `allowComments: true`), but this file is deliberately kept as strict
JSON so that plain JSON tooling (`jq`, pre-commit `check-json` hooks, and
editors that map `*.json` to strict JSON) can parse it without special-casing.
Keep notes like this one in this README rather than as inline comments.
