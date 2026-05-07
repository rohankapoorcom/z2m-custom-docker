# z2m-custom-docker

Build a Zigbee2MQTT Docker image using a custom branch of [zigbee-herdsman](https://github.com/Koenkk/zigbee-herdsman) and/or [zigbee-herdsman-converters](https://github.com/Koenkk/zigbee-herdsman-converters).

The build script packs your local herdsman checkout, rebuilds converters against it, swaps both into Zigbee2MQTT, patches the Dockerfile, and produces a ready-to-run Docker image.

## Prerequisites

- Node.js 24
- pnpm 10
- jq
- Docker
- coreutils (`sha1sum`)

## Local usage

```bash
HERDSMAN_DIR=/path/to/zigbee-herdsman \
HERDSMAN_REPO=your-username/zigbee-herdsman \
HERDSMAN_REF=my-herdsman-branch \
CONVERTERS_DIR=/path/to/zigbee-herdsman-converters \
CONVERTERS_REPO=your-username/zigbee-herdsman-converters \
CONVERTERS_REF=my-converters-branch \
Z2M_DIR=/path/to/zigbee2mqtt \
  ./build.sh
```

This produces a Docker image tagged `zigbee2mqtt:<conv-segment>__<herdsman-segment>` by default.

### Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `HERDSMAN_DIR` | Yes | -- | Path to your zigbee-herdsman checkout |
| `HERDSMAN_REPO` | Yes | -- | Herdsman repo (`owner/repo`), used to stamp the version |
| `HERDSMAN_REF` | Yes | -- | Herdsman branch or tag, used to stamp the version |
| `CONVERTERS_DIR` | Yes | -- | Path to your zigbee-herdsman-converters checkout |
| `CONVERTERS_REPO` | Yes | -- | Converters repo (`owner/repo`), used to stamp the version |
| `CONVERTERS_REF` | Yes | -- | Converters branch or tag, used to stamp the version |
| `Z2M_DIR` | Yes | -- | Path to your zigbee2mqtt checkout |
| `DOCKER_TAG` | No | `zigbee2mqtt:<conv-segment>__<herdsman-segment>` | Tag applied to the built image (derived from both repo/ref pairs) |

### Examples

Build with a custom tag:

```bash
HERDSMAN_DIR=../zigbee-herdsman \
HERDSMAN_REPO=your-username/zigbee-herdsman \
HERDSMAN_REF=my-herdsman-branch \
CONVERTERS_DIR=../zigbee-herdsman-converters \
CONVERTERS_REPO=your-username/zigbee-herdsman-converters \
CONVERTERS_REF=my-converters-branch \
Z2M_DIR=../zigbee2mqtt \
DOCKER_TAG=zigbee2mqtt:my-test \
  ./build.sh
```

Run the resulting image:

```bash
docker run -v /path/to/data:/app/data -p 8080:8080 zigbee2mqtt:my-test
```

## GitHub Actions

The included workflow at `.github/workflows/build.yml` lets you trigger builds from the GitHub UI or CLI without any local tooling. It handles checking out all three repositories for you.

### Trigger from the UI

Go to **Actions > Build Zigbee2MQTT with Custom Converters > Run workflow** and fill in the form:

| Input | Default | Description |
|---|---|---|
| `herdsman_repo` | `Koenkk/zigbee-herdsman` | Herdsman repo (`owner/repo`) |
| `herdsman_ref` | `master` | Branch or tag to build |
| `converters_repo` | `Koenkk/zigbee-herdsman-converters` | Converters repo (`owner/repo`) |
| `converters_ref` | `master` | Branch or tag to build |
| `z2m_repo` | `Koenkk/zigbee2mqtt` | Zigbee2MQTT repo (`owner/repo`) |
| `z2m_ref` | `master` | Zigbee2MQTT branch or tag |
| `push_ghcr` | `true` | Push the image to GitHub Container Registry |

### Trigger from the CLI

```bash
gh workflow run build.yml \
  -f herdsman_repo=your-username/zigbee-herdsman \
  -f herdsman_ref=my-herdsman-branch \
  -f converters_repo=your-username/zigbee-herdsman-converters \
  -f converters_ref=my-converters-branch \
  -f push_ghcr=true
```

### Publishing to GHCR

Docker image tags are derived from both the converters and herdsman repo/ref pairs, joined with `__`. Each side is sanitized to `[a-z0-9.-]` and capped at 50 characters; if a side exceeds the cap, it is truncated to 41 characters and an 8-character sha1 suffix is appended (`<41 chars>-<sha1[:8]>`) so the tag stays short and deterministic.

For example, with `converters_repo=rohankapoorcom/zigbee-herdsman-converters`, `converters_ref=inovelli-lib-cleanup`, `herdsman_repo=Koenkk/zigbee-herdsman`, `herdsman_ref=master`:

- Local: `zigbee2mqtt:rohankapoorcom.zigbee-herdsman-converters.inovelli-lib-cleanup__koenkk.zigbee-herdsman.master`
- GHCR: `ghcr.io/<repo-owner>/zigbee2mqtt-custom:<conv-segment>__<herdsman-segment>-20260328-153000`

When `push_ghcr` is enabled, the workflow pushes the image to:

```
ghcr.io/<repo-owner>/zigbee2mqtt-custom:<conv-segment>__<herdsman-segment>-<timestamp>
```

The `GITHUB_TOKEN` is used for authentication, so no additional secrets are needed. Make sure the repository's **Settings > Actions > General > Workflow permissions** is set to "Read and write permissions" if you want to push packages.

## How it works

`build.sh` performs five steps:

1. **Build and pack zigbee-herdsman** -- runs `pnpm install` and `pnpm pack` in your herdsman checkout, producing a `.tgz` tarball, and copies it into both the converters and zigbee2mqtt directories.
2. **Build and pack converters** -- rewrites converters' `package.json` to point `zigbee-herdsman` at the local herdsman tarball, then runs `pnpm install --no-frozen-lockfile` and `pnpm pack`. This ensures the converters TypeScript build compiles against the same herdsman API surface that runtime will see.
3. **Patch Zigbee2MQTT** -- rewrites `package.json` so both `zigbee-herdsman` and `zigbee-herdsman-converters` point at the local tarballs, and updates the Dockerfile to `COPY` both tarballs. Zigbee2MQTT already declares `pnpm.overrides."zigbee-herdsman": "$zigbee-herdsman"`, so the override automatically propagates the local herdsman to the converters tarball at install time -- no override edit is needed here.
4. **Build Zigbee2MQTT** -- regenerates the lockfile and compiles TypeScript.
5. **Build Docker image** -- runs `docker build` using the patched Dockerfile.

The GitHub Actions workflow handles checking out all three repositories before invoking the script.
