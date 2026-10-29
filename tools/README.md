# Tools for local development

## build-podman.sh

Builds the GitHub Actions Runners manager container image using Podman.

```bash
./build-podman.sh
```

## gce.py

CLI script to manually create and delete runner instances on Google Cloud Platform.
This tool is useful for testing instance creation and deletion logic without triggering the full webhook flow.

**Prerequisites:**
- Install Python dependencies: `uv sync` (from the project root)
- Run the script with `uv run` so it uses the project virtual environment
- Set environment variables: `GOOGLE_CLOUD_PROJECT` and `GOOGLE_CLOUD_ZONE`
- Ensure you have proper GCP credentials configured (e.g., via `gcloud auth application-default login`)

**Usage:**

Create a runner instance:
```bash
uv run tools/gce.py create --token [registration-token] --url [repo-url] --template [template-name]
```

Example:
```bash
uv run tools/gce.py create --token ghp_abc123... --url https://github.com/myorg/myrepo --template gcp-ubuntu-24-04
```

Delete a runner instance:
```bash
uv run tools/gce.py delete --instance [instance-name]
```

Example:
```bash
uv run tools/gce.py delete --instance runner-a1b2c3d4
```