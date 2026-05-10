# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`hcl-dx-local-dev` automates the setup of a local HCL Digital Experience (HCL DX) development environment running inside a k3d Kubernetes cluster, deployed via Helm.

## Architecture

### Technology Stack

| Tool | Role |
|------|------|
| **k3d** | Lightweight Kubernetes cluster (k3s inside Docker) |
| **kubectl** | Cluster interaction and resource management |
| **Helm** | Deploying HCL DX and supporting charts |
| **k9s** | Terminal UI for cluster monitoring |

### Infrastructure Layer Order

```
Docker → k3d cluster → kubectl (cluster access) → Helm (HCL DX deployment)
```

k9s is a monitoring tool, not a deployment dependency.

## Make Targets

The `Makefile` is the sole entry point for all setup and teardown operations. Running `make` with no arguments opens an interactive target menu.

### Menu (default target)

```
make          # Open the interactive target menu
```

The menu is powered by `fzf` if installed (fuzzy search, arrow-key navigation) and falls back to a numbered list otherwise. Selecting a target runs `make <target>`. `fzf` is optional — install it for the better experience but it is not a system prerequisite.

Each target is documented with a `## Description` inline comment, which is what the menu parses. Any new target added to the Makefile must include a `## description` comment to appear in the menu.

### Prerequisites

```
make check-prereqs   # Verify Docker (binary + daemon), curl, and make are present.
                     # Offers to install any missing tool via the detected package
                     # manager (pacman / apt / dnf / brew). Exits non-zero if any
                     # prerequisite remains unresolved.
```

`check-prereqs` is also the first step of `install-all`.

### Resource Analysis

```
make analyze-resources   # Detect system specs, recommend k3d settings, prompt to
                         # accept or override, save to .k3d-config.env
```

Run this before `make install-all`. It writes `.k3d-config.env` (gitignored), which
`configure-k3d` requires. Re-running it overwrites the previous settings.
`clean-k3d` deletes `.k3d-config.env`.

### Cluster Lifecycle

```
make start   # Start the k3d cluster (frees no disk, just stops compute)
make stop    # Stop the k3d cluster to reclaim CPU/RAM on the host
```

The cluster name defaults to `hcl-dx` and can be overridden: `make start CLUSTER_NAME=my-cluster`.

### Per-Tool Targets

Each tool (`k3d`, `kubectl`, `helm`, `k9s`) exposes four targets:

```
install-<tool>     # Download and install the binary
configure-<tool>   # Apply configuration / post-install setup
uninstall-<tool>   # Remove the binary
clean-<tool>       # Remove config files, state, and data
```

### Pipeline Targets

```
make install-all   # Full install pipeline in dependency order
make uninstall-all # Full uninstall and cleanup in reverse order
```

`install-all` requires `.k3d-config.env` to exist (run `make analyze-resources` first).

## Key Files

| File | Purpose |
|------|---------|
| `Makefile` | All install/configure/uninstall/clean/start/stop targets |
| `scripts/menu.sh` | Interactive target menu; uses `fzf` if available, numbered list otherwise |
| `scripts/check-prereqs.sh` | Checks Docker, curl, make; offers to install missing tools |
| `scripts/analyze-resources.sh` | System detection, recommendation logic, interactive prompts |
| `scripts/install-k3d.sh` | Downloads k3d binary; idempotent (skips if version matches) |
| `scripts/configure-k3d.sh` | Generates `config/k3d-cluster.yaml` and creates the k3d cluster |
| `scripts/install-kubectl.sh` | Downloads kubectl binary; idempotent (skips if version matches) |
| `scripts/configure-kubectl.sh` | Sets kubectl context to the k3d cluster; installs bash and fish completions |
| `scripts/install-helm.sh` | Downloads Helm tarball, extracts binary; idempotent (skips if version matches) |
| `scripts/configure-helm.sh` | Adds Helm repositories, updates index, installs bash and fish completions |
| `scripts/install-k9s.sh` | Downloads k9s tarball, extracts binary; idempotent (skips if version matches) |
| `scripts/configure-k9s.sh` | Writes default `~/.config/k9s/config.yaml`; installs bash and fish completions |
| `.k3d-config.env` | Generated resource config (`K3D_CPUS`, `K3D_MEMORY`, `K3D_SERVERS`, `K3D_AGENTS`) — gitignored |
| `config/k3d-cluster.yaml` | Generated k3d cluster config (from `.k3d-config.env`) — gitignored |

## k3d Cluster Config

`configure-k3d` generates `config/k3d-cluster.yaml` using `k3d.io/v1alpha5` and creates the cluster from it. Key settings applied:

- `servers` / `agents` — from `K3D_SERVERS` / `K3D_AGENTS` in `.k3d-config.env`
- `options.runtime.serversMemory` / `agentsMemory` — from `K3D_MEMORY`; sets Docker `--memory` per node
- Host ports `80:80` and `443:443` mapped through the k3d loadbalancer for HCL DX ingress
- `updateDefaultKubeconfig: true` — kubectl context is set automatically on cluster creation
- `K3D_CPUS` from `.k3d-config.env` is informational only; k3d does not expose a per-cluster CPU cap

`configure-k3d` is idempotent: if the cluster already exists it prompts before deleting and recreating.

`install-k3d` is idempotent: skips download if the installed version already matches. Override the version with `K3D_VERSION=v5.x.x make install-k3d`.

## k9s Configuration

`install-k9s` follows the same tarball pattern as Helm but with k9s's release naming convention: `k9s_Linux_amd64.tar.gz` (capital `Linux`, lowercase arch). The binary sits directly in the tarball root, unlike Helm's `linux-amd64/helm` subdirectory. Fetches the latest tag from the GitHub API (`derailed/k9s`), falling back to `v0.32.4`. Override with `K9S_VERSION=v0.x.x make install-k9s`. Idempotent.

`configure-k9s` writes `~/.config/k9s/config.yaml` with sensible defaults (2s refresh rate, 200-line log tail, no mouse). Skips writing the config if the file already exists, preserving any manual customisations. Also installs bash and fish completions.

`clean-k9s` removes the entire `~/.config/k9s/` directory and completion files.

## Helm Configuration

`install-helm` fetches the latest release tag from the GitHub API, falling back to `v3.15.0`. Unlike kubectl and k3d (single binaries), Helm is distributed as a tarball (`helm-<version>-linux-<arch>.tar.gz`); the script extracts and installs the binary via a temp directory with an `EXIT` trap for cleanup. Override with `HELM_VERSION=v3.x.x make install-helm`. Idempotent.

`configure-helm` manages two separate lists at the top of `scripts/configure-helm.sh`:

- **`REPOS`** — traditional Helm repositories added via `helm repo add` (currently: `bitnami`). Idempotent: skips repos already present. `clean-helm` removes these.
- **`OCI_REGISTRIES`** — OCI registries used with `oci://` URLs (currently: `hclcr.io`). OCI registries cannot be added via `helm repo add`; they are listed here for documentation and surfaced at the end of configure output with a login reminder. `helm registry login hclcr.io` is deferred to the HCL DX install step.

Also installs bash and fish completions.

`clean-helm` removes the repositories added by `configure-helm` and the completion files. It does not remove Helm's cache (`~/.cache/helm`) or full config directory.

## kubectl Configuration

`install-kubectl` fetches the latest stable version from `dl.k8s.io/release/stable.txt`, falling back to `v1.30.0` if unavailable. Override with `KUBECTL_VERSION=v1.x.x make install-kubectl`. Idempotent: skips if installed version matches.

`configure-kubectl` expects the k3d cluster to already exist. It:
1. Switches the active context to `k3d-<CLUSTER_NAME>` (k3d prefixes all context names with `k3d-`)
2. Verifies API server connectivity; exits with guidance if unreachable
3. Installs shell completions — bash (`/etc/bash_completion.d/kubectl`) and fish (`~/.config/fish/completions/kubectl.fish`) if those shells are present

`clean-kubectl` removes only the completion files; it does not touch the kubeconfig (context entries are managed by k3d).

## Design Decisions

- **k3d over k3s/minikube**: Chosen for fast cluster create/delete cycles during development. k3d wraps k3s in Docker containers, giving production-like Kubernetes with minimal overhead.
- **Make as orchestrator**: Single interface for all install/configure/uninstall/clean/start/stop operations, with pipeline targets for full setup and teardown.
- **`.k3d-config.env` is host-specific and gitignored**: Resource settings vary per machine; `analyze-resources` generates them interactively and saves locally.
- **`config/k3d-cluster.yaml` is generated and gitignored**: Derived from `.k3d-config.env`; regenerated each time `configure-k3d` runs.
- **`start`/`stop` separate from `install`/`uninstall`**: Allows the cluster to be suspended and resumed without reinstalling, freeing host CPU/RAM when HCL DX is not needed.
- **HCL DX resource requirements**: HCL DX is resource-intensive (16 GB+ RAM recommended). `analyze-resources` reserves 2 CPUs and 4 GB for the host by default.
