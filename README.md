# hcl-dx-local-dev

A Make-driven toolkit for provisioning a local [HCL Digital Experience (DX)](https://www.hcl-software.com/dx) development environment on Linux. It installs and configures a lightweight Kubernetes cluster (k3d) and the supporting toolchain (kubectl, Helm, k9s), then deploys HCL DX via Helm from the HCL Harbor registry.

Running `make` opens an interactive menu of all available targets (fuzzy-searchable with [fzf](https://github.com/junegunn/fzf), numbered list otherwise).

## Stack

| Tool | Role |
|------|------|
| [k3d](https://k3d.io) | Lightweight Kubernetes cluster (k3s inside Docker) |
| [kubectl](https://kubernetes.io/docs/reference/kubectl/) | Cluster interaction and resource management |
| [Helm](https://helm.sh) | Chart-based deployment of HCL DX |
| [k9s](https://k9scli.io) | Terminal UI for cluster monitoring |

---

## Prerequisites

- **Docker** — required by k3d (daemon must be running)
- **curl** — used to download binaries
- **make** — orchestrates all targets

Run `make check-prereqs` to verify these are present; it will offer to install any that are missing via your system package manager (pacman, apt, dnf, or brew).

You also need **HCL Harbor credentials** to pull DX images and charts:
- Log in at [hclcr.io](https://hclcr.io), navigate to your User Profile, and copy the **CLI secret** (this is your `HCL_PASS`, not your account password).

---

## Full Installation Guide

This is the complete sequence from a fresh clone to a running HCL DX environment.

### 1. Check prerequisites

```bash
make check-prereqs
```

Verifies Docker (binary + daemon), curl, and make. Offers to install anything missing.

### 2. Analyse system resources

```bash
make analyze-resources
```

Detects available CPU and RAM, recommends k3d cluster settings, and writes them to `local.env`. You can accept the recommendation or enter custom values.

> **HCL DX is resource-intensive.** 16 GB RAM or more on the host is recommended.

### 3. Configure `local.env`

`local.env` is created automatically the first time any `make` target runs. Open it and fill in the required values before proceeding:

```bash
# ── Registry ───────────────────────────────────────────────────────────────────
HCL_REGISTRY=hclcr.io
HCL_USER=your-email@example.com      # your HCL Harbor username
HCL_PASS=your-harbor-cli-secret      # CLI secret from your Harbor profile (not your password)

# ── HCL DX ─────────────────────────────────────────────────────────────────────
DX_VERSION=2.40.0                    # Helm chart semantic version for the CF release you want
DX_NAMESPACE=dxns                    # Kubernetes namespace
DX_RELEASE=dx                        # Helm release name
DX_REGISTRY_SECRET=dx-harbor         # Name of the image pull secret (default is fine)
EDITOR=vi                            # Editor opened when customising the values file
```

The k3d settings (`K3D_SERVERS`, `K3D_AGENTS`, `K3D_MEMORY`, etc.) are set by `make analyze-resources` and do not need to be edited manually.

To find the correct `DX_VERSION` for a given CF release, use the legacy repo method after setting your credentials:

```bash
helm repo add --username "$HCL_USER" --password "$HCL_PASS" hcl-dx https://hclcr.io/chartrepo/dx
helm search repo hcl-dx/hcl-dx-deployment --versions
```

### 4. Install the toolchain

```bash
make install-all
```

This runs the full pipeline in order:

```
check-prereqs
→ install-k3d      → configure-k3d       (cluster created)
→ install-kubectl  → configure-kubectl    (context set)
→ install-helm     → configure-helm       (repos added)
→ install-k9s      → configure-k9s        (monitoring tool)
→ configure-dx                             (namespace created, DX settings saved)
→ install-dx                               (interactive — see below)
```

> **Note:** Run `make analyze-resources` before `make install-all` to size the cluster to your hardware. If you skip this, the defaults in `local.env` are used (1 server, 2 agents, 8 GB memory per node).

### 5. What happens during `make install-dx`

`install-dx` is the interactive DX deployment step. It performs these actions automatically in sequence:

1. **Pulls the Helm chart** from `hclcr.io` to `charts/<version>/hcl-dx-deployment/` if not already present. The original tarball is kept at `charts/<version>/hcl-dx-deployment-<version>.tgz` as a reset point.
2. **Pulls the default values** from the chart to `charts/<version>/dx-values-reference.yaml` if not already present.
3. **Creates `charts/<version>/dx-values.yaml`** as a copy of the reference file if it does not yet exist.
4. **Opens the values file in your editor** (`EDITOR` in `local.env`, default `vi`). At minimum, add the image pull secret configuration:
   ```yaml
   images:
     repository: "hclcr.io"
     imagePullSecrets:
       - name: "dx-harbor"
   ```
   Adjust resource limits, storage class, or any other settings for your environment, then save and exit.
5. **Creates the image pull secret** (`dx-harbor`) in the DX namespace so Kubernetes can pull images from `hclcr.io`.
6. **Creates a self-signed TLS secret** (`dx-tls-cert`) required by the HAProxy ingress controller. A 10-year self-signed certificate is generated automatically; browsers will show an untrusted-certificate warning which is expected for local dev.
7. **Runs `helm upgrade --install`** using the local chart and your edited values file. Install and upgrade are handled by the same target.

After `install-dx` completes, run `make configure-dx-ingress` once to create the Traefik TCP passthrough route that exposes DX at `https://localhost`.

> **Storage class note:** k3d's built-in `local-path` StorageClass only supports `ReadWriteOnce`. The chart defaults (`storageClassName: manual`, access mode `ReadWriteMany` on the profile and DAM PVCs) are incompatible with k3d out of the box. The `volumes:` section in `dx-values.yaml` overrides all storage classes to `local-path`, and the chart templates in `charts/<version>/hcl-dx-deployment/templates/` have been patched to use `ReadWriteOnce`. **This means the local install supports only a single replica of each service** — do not increase replica counts beyond 1 in a k3d environment.

DX pods typically take **20–30 minutes** to reach a ready state. Monitor progress with:

```bash
k9s -n dxns
# or
kubectl get pods -n dxns -w
```

---

## Daily Use

```bash
make start    # start the k3d cluster (resume after stopping)
make stop     # stop the cluster and free CPU/RAM — data is preserved
make open-dx  # open HCL DX in the browser at https://localhost
```

`make open-dx` opens `https://localhost/wps/portal` in your default browser. Accept the self-signed certificate warning — this is expected for local dev.

Traffic reaches DX without any port-forward via Traefik, which k3s includes and k3d already maps to host ports 80/443:

```
Browser → https://localhost:443
  → k3d lb → Traefik (TCP passthrough, HostSNI: localhost)
  → dx-haproxy service:443
  → HAProxy pod → WAS core:10042
```

Traefik uses TCP passthrough (not HTTP proxying), so HAProxy terminates TLS itself and the browser's `Host: localhost` header reaches WAS unchanged. Run `make configure-dx-ingress` to create or recreate the Traefik route if needed.

The cluster name defaults to `hcl-dx` and can be overridden on any target:

```bash
make start CLUSTER_NAME=my-cluster
```

---

## Upgrading HCL DX

To upgrade to a new CF release:

1. Update `DX_VERSION` in `local.env` to the new chart version.
2. Run `make pull-dx-chart` — downloads and extracts the new version to its own `charts/<new-version>/` folder without touching your existing version.
3. Run `make pull-dx-values` — saves the new version's default values to `charts/<new-version>/dx-values-reference.yaml`.
4. Copy and adapt your previous `charts/<old-version>/dx-values.yaml` to `charts/<new-version>/dx-values.yaml`, merging in any new defaults from the reference file.
5. Run `make install-dx` — detects the existing release and performs a `helm upgrade`.

Each version lives in its own `charts/<version>/` folder, so you can roll back by changing `DX_VERSION` and re-running `make install-dx`.

---

## Resetting a Locally Edited Chart

If you have edited files inside `charts/<version>/hcl-dx-deployment/` and want to restore the originals:

```bash
make reset-dx-chart
```

This re-extracts from the tarball in `charts/<version>/`, prompting for confirmation before overwriting your changes.

---

## Teardown

```bash
make uninstall-all
```

Tears down everything in reverse order:

```
uninstall-dx  → clean-dx
→ clean-k9s   → uninstall-k9s
→ clean-helm  → uninstall-helm
→ clean-kubectl → uninstall-kubectl
→ clean-k3d   → uninstall-k3d
```

> `local.env` and `charts/` are **not** removed by teardown — your credentials and downloaded charts are preserved across reinstalls.

---

## Configuration Reference (`local.env`)

`local.env` is created automatically on first run and is never tracked in git. All make targets read from it.

| Variable | Default | Description |
|---|---|---|
| `HCL_REGISTRY` | `hclcr.io` | HCL Harbor registry hostname |
| `HCL_USER` | _(required)_ | Harbor username (email address) |
| `HCL_PASS` | _(required)_ | Harbor CLI secret (from your profile) |
| `CLUSTER_NAME` | `hcl-dx` | k3d cluster name |
| `K3D_SERVERS` | `1` | Number of k3s server nodes |
| `K3D_AGENTS` | `2` | Number of k3s agent nodes |
| `K3D_CPUS` | `4` | Informational — k3d has no per-cluster CPU cap |
| `K3D_MEMORY` | `8g` | Docker memory limit per node |
| `DX_VERSION` | _(required)_ | Helm chart version for HCL DX (e.g. `2.40.0`) |
| `DX_NAMESPACE` | `dxns` | Kubernetes namespace for DX |
| `DX_RELEASE` | `dx` | Helm release name |
| `DX_REGISTRY_SECRET` | `dx-harbor` | Name of the image pull secret |
| `DX_TLS_SECRET` | `dx-tls-cert` | Name of the TLS secret used by HAProxy (self-signed cert auto-generated) |
| `EDITOR` | `vi` | Editor for reviewing the DX values file |
| `DX_SEARCH_VERSION` | _(optional)_ | Helm chart version for DX Search v2 |
| `DX_SEARCH_RELEASE` | `dx-search` | Helm release name for DX Search v2 |

---

## Make Target Reference

### Pipelines

| Target | Description |
|---|---|
| `install-all` | Full install: toolchain + DX (interactive) |
| `uninstall-all` | Full teardown in reverse order |

### Cluster Lifecycle

| Target | Description |
|---|---|
| `start` | Start the k3d cluster |
| `stop` | Stop the cluster and free CPU/RAM |

### Prerequisites

| Target | Description |
|---|---|
| `check-prereqs` | Verify Docker, curl, make; offer to install missing tools |
| `analyze-resources` | Detect system resources; set k3d config in `local.env` |

### Per-tool (k3d, kubectl, Helm, k9s)

Each tool exposes four targets: `install-<tool>`, `configure-<tool>`, `uninstall-<tool>`, `clean-<tool>`.

### HCL DX

| Target | Description |
|---|---|
| `configure-dx` | Create DX namespace; save DX settings to `local.env` |
| `pull-dx-chart` | Download and extract DX chart to `charts/<version>/` |
| `pull-dx-values` | Save default chart values to `charts/<version>/dx-values-reference.yaml` |
| `reset-dx-chart` | Re-extract chart from tarball, discarding local edits |
| `create-dx-secret` | Create the `hclcr.io` image pull secret in the DX namespace |
| `install-dx` | Full interactive install/upgrade: pull chart → edit values → create secret → deploy |
| `uninstall-dx` | Uninstall the HCL DX Helm release |
| `clean-dx` | Delete the DX namespace |
