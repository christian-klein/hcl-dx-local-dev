# hcl-dx-local-dev

A Make-driven toolkit for provisioning a local [HCL Digital Experience (DX)](https://www.hcl-software.com/dx) development environment on Linux. It installs and configures a lightweight Kubernetes cluster (k3d) and the supporting toolchain (kubectl, Helm, k9s), then deploys HCL DX via Helm.

## Overview

Running `make` opens an interactive menu of all available targets. If [fzf](https://github.com/junegunn/fzf) is installed the menu is fuzzy-searchable; otherwise it falls back to a numbered list.

```
make                  # interactive menu (default)
make install-all      # full install pipeline
make uninstall-all    # full teardown pipeline
make start            # start the k3d cluster
make stop             # stop the k3d cluster and free resources
```

**Recommended first-time flow:**

```bash
make check-prereqs      # verify Docker, curl, make are present
make analyze-resources  # size the cluster to your machine
make install-all        # install and configure everything
```

## Stack

| Tool | Role |
|------|------|
| [k3d](https://k3d.io) | Lightweight Kubernetes cluster (k3s inside Docker) |
| [kubectl](https://kubernetes.io/docs/reference/kubectl/) | Cluster interaction and resource management |
| [Helm](https://helm.sh) | Chart-based deployment of HCL DX |
| [k9s](https://k9scli.io) | Terminal UI for cluster monitoring |

## Prerequisites

- **Docker** — required by k3d (daemon must be running)
- **curl** — used to download binaries
- **make** — orchestrates all targets

Run `make check-prereqs` to verify these are present; it will offer to install any that are missing via your system package manager (pacman, apt, dnf, or brew).

## Make Targets

### `make check-prereqs`

Checks for Docker (binary and daemon), curl, and make. For each missing tool it detects your package manager and offers to install it. Exits non-zero if any prerequisite remains unresolved, blocking the pipeline.

### `make analyze-resources`

Reads total CPU and RAM from the host and recommends k3d cluster settings, reserving 2 CPUs and 4 GB for the host OS. You can accept the recommendation or enter custom values. Settings are saved to `.k3d-config.env` (gitignored) and consumed by `configure-k3d`.

```
K3D_CPUS      # CPU cores to allocate per node
K3D_MEMORY    # Memory per node (e.g. 8g)
K3D_SERVERS   # Number of server nodes (default: 1)
K3D_AGENTS    # Number of agent nodes (default: 2)
```

### `make install-k3d` / `make configure-k3d`

`install-k3d` downloads the k3d binary from GitHub releases. Idempotent — skips the download if the installed version already matches. Override the version with `K3D_VERSION=v5.x.x make install-k3d`.

`configure-k3d` generates `config/k3d-cluster.yaml` from `.k3d-config.env` and creates the cluster. Key cluster settings:

- Server and agent counts from `K3D_SERVERS` / `K3D_AGENTS`
- Per-node Docker memory limit from `K3D_MEMORY`
- Host ports `80` and `443` mapped through the k3d loadbalancer for HCL DX ingress
- kubectl context set automatically on creation (`k3d-hcl-dx` by default)

If the cluster already exists, you are prompted before it is deleted and recreated.

### `make install-kubectl` / `make configure-kubectl`

`install-kubectl` downloads kubectl from `dl.k8s.io`, resolving the latest stable version automatically. Override with `KUBECTL_VERSION=v1.x.x make install-kubectl`.

`configure-kubectl` switches the active kubectl context to `k3d-<CLUSTER_NAME>`, verifies API server connectivity, and installs shell completions for bash and fish.

### `make install-helm` / `make configure-helm`

`install-helm` downloads the Helm tarball from GitHub releases and extracts the binary. Override with `HELM_VERSION=v3.x.x make install-helm`.

`configure-helm` manages two categories of Helm sources:

- **Traditional repositories** (e.g. `bitnami`) — added via `helm repo add` and updated with `helm repo update`
- **OCI registries** (e.g. `hclcr.io`) — listed for documentation; `helm registry login` is deferred to the HCL DX installation step

Both lists are defined as arrays at the top of `scripts/configure-helm.sh`. Shell completions for bash and fish are also installed.

### `make install-k9s` / `make configure-k9s`

`install-k9s` downloads the k9s tarball from GitHub releases (`derailed/k9s`). Override with `K9S_VERSION=v0.x.x make install-k9s`.

`configure-k9s` writes a default `~/.config/k9s/config.yaml` (2 s refresh rate, 200-line log tail) and installs shell completions. The config file is not overwritten if it already exists, preserving manual customisations.

### `make start` / `make stop`

Start or stop the k3d cluster without destroying it. Use `stop` to free CPU and RAM when HCL DX is not needed, and `start` to resume without reinstalling anything.

The cluster name defaults to `hcl-dx` and can be overridden on any target:

```bash
make start CLUSTER_NAME=my-cluster
```

### `make install-all` / `make uninstall-all`

`install-all` runs the full pipeline in dependency order:

```
check-prereqs → install-k3d → configure-k3d → install-kubectl → configure-kubectl
             → install-helm → configure-helm → install-k9s → configure-k9s
```

`uninstall-all` runs the full teardown in reverse order, removing binaries and configuration for every tool.

> **Note:** Run `make analyze-resources` before `make install-all` to generate the required `.k3d-config.env`.

## HCL DX Installation

Helm deployment of HCL DX against the cluster is handled by a separate set of targets (coming soon). The HCL Harbor registry at `oci://hclcr.io` is pre-registered as a known OCI source. Before deploying, authenticate with:

```bash
helm registry login hclcr.io --username <user> --password <token>
```
