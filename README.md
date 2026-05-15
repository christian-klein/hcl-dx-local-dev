# hcl-dx-local-dev

A Make-driven toolkit for provisioning a local [HCL Digital Experience (DX)](https://www.hcl-software.com/dx) development environment on Linux. It installs and configures a lightweight Kubernetes cluster (k3d) and the supporting toolchain (kubectl, Helm, k9s), then deploys HCL DX via Helm from the HCL Harbor registry.

Running `make` opens an interactive menu of all available targets (fuzzy-searchable with [fzf](https://github.com/junegunn/fzf), numbered list otherwise).

DX versions:

https://help.hcl-software.com/digital-experience/9.5/CF235/get_started/download/harbor_container_registry/#helm-chart-and-cf-versions

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

1. **Pulls the Helm chart** from `hclcr.io` to `charts/dx/<version>/hcl-dx-deployment/` if not already present. The original tarball is kept at `charts/dx/<version>/hcl-dx-deployment-<version>.tgz` as a reset point.
2. **Pulls the default values** from the chart to `charts/dx/<version>/dx-values-reference.yaml` if not already present.
3. **Creates `charts/dx/<version>/dx-values.yaml`** as a copy of the reference file if it does not yet exist.
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

## HCL DX Search v2

DX Search v2 is a separate Helm chart (`hcl-dx-search`) installed independently into the same namespace as DX. The version is controlled by `DX_SEARCH_VERSION` in `local.env`.

> **Note:** This local setup runs a single-replica OpenSearch cluster. DX Search v2 is not configured for high availability in this environment.

```bash
make install-search
```

`install-search` is fully automated. It runs these steps in order:

1. **OpenSearch kernel prerequisite** — sets `vm.max_map_count=262144` on the host (k3d nodes share the host kernel). Requires `sudo` on first run; persists to `/etc/sysctl.d/99-dx-opensearch.conf`.
2. **Namespace** — creates `DX_NAMESPACE` if it does not already exist.
3. **Chart** — pulls `hcl-dx-search` to `charts/search/<version>/hcl-dx-search/` if not already present.
4. **Reference values** — generates `charts/search/<version>/search-values-reference.yaml` from the chart if not already present.
5. **TLS certificates** — generates a root CA, admin, node, and client certificate using OpenSSL. Certs are stored in `charts/search/<version>/certs/` (gitignored). Creates three k8s secrets in the DX namespace: `search-admin-cert`, `search-node-cert`, `search-client-cert`. Idempotent — skips if certs already exist.
6. **Local overrides** — writes `charts/search/<version>/search-values-local.yaml` with the image registry, image pull secret, `local-path` StorageClass for both OpenSearch volumes, and the DX deployment name. This file is always regenerated and merged _after_ your values file so it always wins.
7. **Editor** — opens `charts/search/<version>/search-values.yaml` for you to add any additional overrides (image pull secrets, resource limits, replica counts, etc.).
8. **Helm install/upgrade** — runs `helm upgrade --install` with both values files.
9. **OpenSearch security init** — waits for the OpenSearch pod to be ready, generates a bcrypt-hashed `admin` user via OpenSearch's own `hash.sh` tool, writes it into `internal_users.yml` inside the pod, then runs `securityadmin.sh` to push the full security configuration to OpenSearch's internal index. This is required on every fresh install and after any certificate rotation. Re-run manually with `make init-search-security`.
10. **DX wiring** — writes `charts/dx/<version>/dx-search-values.yaml` with all required Search v2 settings (`applications.remoteSearch: false`, `networking.searchMiddlewareService`, `configuration.searchMiddleware`, `configuration.core.search` v2 flags) and runs `helm upgrade` on the DX release. `install-dx` automatically picks up this overlay on subsequent runs. `uninstall-search` re-runs the DX upgrade without the overlay, restoring chart defaults (Remote Search re-enabled, v1 search settings).

Individual targets for each step are also available: `configure-search-prereqs`, `create-search-certs`, `init-search-security`, `pull-search-chart`, `pull-search-values`, `reset-search-chart`, `uninstall-search`, `clean-search`.

---

## Upgrading HCL DX

To upgrade to a new CF release:

1. Update `DX_VERSION` in `local.env` to the new chart version.
2. Run `make pull-dx-chart` — downloads and extracts the new version to its own `charts/dx/<new-version>/` folder without touching your existing version.
3. Run `make pull-dx-values` — saves the new version's default values to `charts/dx/<new-version>/dx-values-reference.yaml`.
4. Copy and adapt your previous `charts/dx/<old-version>/dx-values.yaml` to `charts/dx/<new-version>/dx-values.yaml`, merging in any new defaults from the reference file.
5. Run `make install-dx` — detects the existing release and performs a `helm upgrade`.

Each version lives in its own `charts/<version>/` folder, so you can roll back by changing `DX_VERSION` and re-running `make install-dx`.

---

## Resetting a Locally Edited Chart

If you have edited files inside `charts/dx/<version>/hcl-dx-deployment/` and want to restore the originals:

```bash
make reset-dx-chart
```

This re-extracts from the tarball in `charts/dx/<version>/`, prompting for confirmation before overwriting your changes.

---

## Laptop Sleep / Wake

After the laptop resumes from sleep, k3d nodes lose network/DNS connectivity and pods that need to pull images enter `ImagePullBackOff`.

The fix is a clean k3d cluster stop/start — **not** a Docker restart. Restarting Docker clears the containerd image cache inside the k3d nodes. If HCL has since removed the image tags your chart references from their registry (which they do periodically), the pods will be unable to re-pull and will stay broken until you update chart versions.

### Automatic fix (recommended)

Install a systemd sleep hook that stops and starts the k3d cluster on every resume:

```bash
sudo make install-sleep-hook
```

This creates `/etc/systemd/system-sleep/hcl-dx-k3d-resume`. The cluster restarts with fresh networking and the containerd image cache is preserved; stuck pods retry and clear on their own.

To remove it:

```bash
sudo make uninstall-sleep-hook
```

### Manual fix

If the hook is not installed, or pods are still stuck after a resume:

```bash
make resume
```

Stops and starts the k3d cluster to restore networking without touching Docker or the containerd image cache.

---

## Local Registry

The k3d cluster includes a local Docker registry (`k3d-dx-registry`) on port `5001` (configurable via `REGISTRY_PORT` in `local.env`). It is configured as a transparent mirror for `hclcr.io`, so pods pull from the local registry automatically — no chart or image reference changes required.

### Why use the local registry

- **Offline use** — once images are loaded, the cluster runs without internet access.
- **Version stability** — HCL periodically removes old image tags from their registry. Images cached locally remain available even after the upstream tag is deleted.
- **Faster pod startup** — pulls from `localhost:5001` instead of the internet.

### Loading images

```bash
make load-images
```

Reads the image list from the rendered Helm templates for both the DX and Search v2 charts, checks which images are already cached, then pulls the missing ones from `hclcr.io`, retags them, and pushes them to the local registry. Requires `HCL_USER` and `HCL_PASS` to be set in `local.env` and the cluster to be running.

```bash
make check-images
```

Reports the cache status (present / missing) for every image referenced by the current chart versions without pulling anything.

### Managing cached images

```bash
make wipe-registry                               # delete all cached images (prompts for confirmation)
make delete-image IMAGE=hclcr.io/dx-compose/name:tag  # remove one specific image
```

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
| `REGISTRY_PORT` | `5001` | Host port for the local k3d image registry |
| `K3D_SERVERS` | `1` | Number of k3s server nodes |
| `K3D_AGENTS` | `2` | Number of k3s agent nodes |
| `K3D_CPUS` | `4` | Informational — k3d has no per-cluster CPU cap |
| `K3D_MEMORY` | `8g` | Docker memory limit per node |
| `DX_VERSION` | _(required)_ | Helm chart version for HCL DX (e.g. `2.40.0`) |
| `DX_NAMESPACE` | `dxns` | Kubernetes namespace for DX |
| `DX_RELEASE` | `dx` | Helm release name |
| `DX_REGISTRY_SECRET` | `dx-harbor` | Name of the image pull secret |
| `DX_CHART_REPO` | `hclcr.io/dx/hcl-dx-deployment` | OCI path to the DX Helm chart (without `oci://` prefix) |
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
| `patch-dx-chart` | Patch DX chart PVC templates for `local-path` (`ReadWriteMany` → `ReadWriteOnce`) |
| `create-dx-secret` | Create the `hclcr.io` image pull secret in the DX namespace |
| `install-dx` | Full interactive install/upgrade: pull chart → edit values → create secret → deploy |
| `configure-dx-ingress` | Create Traefik TCP passthrough route so DX is reachable at `https://localhost` |
| `open-dx` | Open HCL DX in the browser at `https://localhost/wps/portal` |
| `uninstall-dx` | Uninstall the HCL DX Helm release |
| `clean-dx` | Delete the DX namespace |

### HCL DX Search v2

| Target | Description |
|---|---|
| `pull-search-chart` | Download and extract the DX Search v2 chart to `charts/search/<version>/` |
| `pull-search-values` | Save default chart values to `charts/search/<version>/search-values-reference.yaml` |
| `reset-search-chart` | Re-extract chart from tarball, discarding local edits |
| `configure-search-prereqs` | Set `vm.max_map_count=262144` on the host (required by OpenSearch) |
| `create-search-certs` | Generate TLS certs and create `search-admin-cert`, `search-node-cert`, `search-client-cert` secrets |
| `init-search-security` | Push security config to OpenSearch's internal index (required after install or cert rotation) |
| `install-search` | Full automated install/upgrade: prereqs → certs → chart → values → deploy → security init → wire DX |
| `uninstall-search` | Uninstall the DX Search v2 Helm release |
| `clean-search` | Remove generated DX Search v2 files |

### Laptop

| Target | Description |
|---|---|
| `resume` | Stop and restart the k3d cluster after laptop sleep (fixes ImagePullBackOff) |
| `install-sleep-hook` | Install systemd hook to auto-restart k3d on every resume (requires sudo) |
| `uninstall-sleep-hook` | Remove the systemd sleep hook (requires sudo) |

### Local Registry

| Target | Description |
|---|---|
| `load-images` | Pull HCL images for the current chart versions and cache in the local registry |
| `check-images` | Show which images for the current chart versions are cached locally |
| `wipe-registry` | Delete all images from the local registry (prompts for confirmation) |
| `delete-image` | Remove one image: `make delete-image IMAGE=hclcr.io/dx-compose/name:tag` |
