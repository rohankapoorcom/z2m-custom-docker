# z2m-custom-docker

Build a Zigbee2MQTT Docker image using a custom branch of [zigbee-herdsman-converters](https://github.com/Koenkk/zigbee-herdsman-converters).

The build script clones the official Zigbee2MQTT repo, swaps in your converters build, patches the Dockerfile, and produces a ready-to-run Docker image.

## Prerequisites

- Node.js 24
- pnpm 10
- jq
- Docker
- git

## Local usage

```bash
CONVERTERS_DIR=/path/to/zigbee-herdsman-converters ./build.sh
```

This produces a Docker image tagged `zigbee2mqtt:custom-converters` by default.

### Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `CONVERTERS_DIR` | Yes | -- | Path to your zigbee-herdsman-converters checkout |
| `Z2M_REPO` | No | `Koenkk/zigbee2mqtt` | Zigbee2MQTT repo (`owner/repo` or full URL) |
| `Z2M_REF` | No | `master` | Zigbee2MQTT branch or tag to build from |
| `DOCKER_TAG` | No | `zigbee2mqtt:custom-converters` | Tag applied to the built image |
| `WORK_DIR` | No | `./build` | Scratch directory for the z2m clone |

### Examples

Build against a specific Zigbee2MQTT release:

```bash
CONVERTERS_DIR=../zigbee-herdsman-converters \
Z2M_REF=2.9.1 \
DOCKER_TAG=zigbee2mqtt:my-test \
  ./build.sh
```

Run the resulting image:

```bash
docker run -v /path/to/data:/app/data -p 8080:8080 zigbee2mqtt:custom-converters
```

## GitHub Actions

The included workflow at `.github/workflows/build.yml` lets you trigger builds from the GitHub UI or CLI without any local tooling.

### Trigger from the UI

Go to **Actions > Build Zigbee2MQTT with Custom Converters > Run workflow** and fill in the form:

| Input | Default | Description |
|---|---|---|
| `converters_repo` | `Koenkk/zigbee-herdsman-converters` | Converters repo (`owner/repo`) |
| `converters_ref` | `master` | Branch or tag to build |
| `z2m_repo` | `Koenkk/zigbee2mqtt` | Zigbee2MQTT repo (`owner/repo`) |
| `z2m_ref` | `master` | Zigbee2MQTT branch or tag |
| `docker_tag` | `zigbee2mqtt:custom-converters` | Image tag used during build |
| `push_ghcr` | `true` | Push the image to GitHub Container Registry |

### Trigger from the CLI

```bash
gh workflow run build.yml \
  -f converters_repo=your-username/zigbee-herdsman-converters \
  -f converters_ref=my-feature-branch \
  -f push_ghcr=true
```

### Publishing to GHCR

When `push_ghcr` is enabled, the workflow pushes the image to:

```
ghcr.io/<repo-owner>/zigbee2mqtt-custom:<timestamp>
```

The `GITHUB_TOKEN` is used for authentication, so no additional secrets are needed. Make sure the repository's **Settings > Actions > General > Workflow permissions** is set to "Read and write permissions" if you want to push packages.

## How it works

`build.sh` performs five steps:

1. **Clone Zigbee2MQTT** at the requested ref (shallow clone).
2. **Build and pack converters** -- runs `pnpm install` and `pnpm pack` in your converters checkout, producing a `.tgz` tarball.
3. **Patch Zigbee2MQTT** -- rewrites `package.json` to point `zigbee-herdsman-converters` at the local tarball, and updates the Dockerfile to include it.
4. **Build Zigbee2MQTT** -- regenerates the lockfile and compiles TypeScript.
5. **Build Docker image** -- runs `docker build` using the patched Dockerfile.

All intermediate files are written to `WORK_DIR` (default `./build`), keeping your source trees clean.
