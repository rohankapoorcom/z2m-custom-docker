# z2m-custom-docker

Build a Zigbee2MQTT Docker image using a custom branch of [zigbee-herdsman-converters](https://github.com/Koenkk/zigbee-herdsman-converters).

The build script swaps in your converters build, patches the Dockerfile, and produces a ready-to-run Docker image.

## Prerequisites

- Node.js 24
- pnpm 10
- jq
- Docker

## Local usage

```bash
CONVERTERS_DIR=/path/to/zigbee-herdsman-converters \
CONVERTERS_REPO=your-username/zigbee-herdsman-converters \
CONVERTERS_REF=my-branch \
Z2M_DIR=/path/to/zigbee2mqtt \
  ./build.sh
```

This produces a Docker image tagged `zigbee2mqtt:custom-converters` by default.

### Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `CONVERTERS_DIR` | Yes | -- | Path to your zigbee-herdsman-converters checkout |
| `CONVERTERS_REPO` | Yes | -- | Converters repo (`owner/repo`), used to stamp the version |
| `CONVERTERS_REF` | Yes | -- | Converters branch or tag, used to stamp the version |
| `Z2M_DIR` | Yes | -- | Path to your zigbee2mqtt checkout |
| `DOCKER_TAG` | No | `zigbee2mqtt:<repo>.<branch>` | Tag applied to the built image (derived from converters repo/ref) |

### Examples

Build with a custom tag:

```bash
CONVERTERS_DIR=../zigbee-herdsman-converters \
CONVERTERS_REPO=your-username/zigbee-herdsman-converters \
CONVERTERS_REF=my-branch \
Z2M_DIR=../zigbee2mqtt \
DOCKER_TAG=zigbee2mqtt:my-test \
  ./build.sh
```

Run the resulting image:

```bash
docker run -v /path/to/data:/app/data -p 8080:8080 zigbee2mqtt:custom-converters
```

## GitHub Actions

The included workflow at `.github/workflows/build.yml` lets you trigger builds from the GitHub UI or CLI without any local tooling. It handles checking out both repositories for you.

### Trigger from the UI

Go to **Actions > Build Zigbee2MQTT with Custom Converters > Run workflow** and fill in the form:

| Input | Default | Description |
|---|---|---|
| `converters_repo` | `Koenkk/zigbee-herdsman-converters` | Converters repo (`owner/repo`) |
| `converters_ref` | `master` | Branch or tag to build |
| `z2m_repo` | `Koenkk/zigbee2mqtt` | Zigbee2MQTT repo (`owner/repo`) |
| `z2m_ref` | `master` | Zigbee2MQTT branch or tag |
| `push_ghcr` | `true` | Push the image to GitHub Container Registry |

### Trigger from the CLI

```bash
gh workflow run build.yml \
  -f converters_repo=your-username/zigbee-herdsman-converters \
  -f converters_ref=my-feature-branch \
  -f push_ghcr=true
```

### Publishing to GHCR

Docker image tags are derived from the converters repo and branch. For example, with `converters_repo=rohankapoorcom/zigbee-herdsman-converters` and `converters_ref=inovelli-lib-cleanup`:

- Local: `zigbee2mqtt:rohankapoorcom.zigbee-herdsman-converters.inovelli-lib-cleanup`
- GHCR: `ghcr.io/<repo-owner>/zigbee2mqtt-custom:rohankapoorcom.zigbee-herdsman-converters.inovelli-lib-cleanup-20260328-153000`

When `push_ghcr` is enabled, the workflow pushes the image to:

```
ghcr.io/<repo-owner>/zigbee2mqtt-custom:<repo>.<branch>-<timestamp>
```

The `GITHUB_TOKEN` is used for authentication, so no additional secrets are needed. Make sure the repository's **Settings > Actions > General > Workflow permissions** is set to "Read and write permissions" if you want to push packages.

## How it works

`build.sh` performs four steps:

1. **Build and pack converters** -- runs `pnpm install` and `pnpm pack` in your converters checkout, producing a `.tgz` tarball.
2. **Patch Zigbee2MQTT** -- rewrites `package.json` to point `zigbee-herdsman-converters` at the local tarball, and updates the Dockerfile to include it.
3. **Build Zigbee2MQTT** -- regenerates the lockfile and compiles TypeScript.
4. **Build Docker image** -- runs `docker build` using the patched Dockerfile.

The GitHub Actions workflow handles checking out both repositories before invoking the script.
