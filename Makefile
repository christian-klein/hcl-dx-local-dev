SHELL        := /bin/bash
CLUSTER_NAME ?= hcl-dx
LOCAL_ENV    := local.env

.DEFAULT_GOAL := menu

-include $(LOCAL_ENV)

# Fallbacks if local.env is missing or incomplete
CLUSTER_NAME ?= hcl-dx
DX_NAMESPACE ?= dxns
DX_RELEASE   ?= dx

_INSTALL_DEPS   := check-prereqs \
                   install-k3d configure-k3d \
                   install-kubectl configure-kubectl \
                   install-helm configure-helm \
                   install-k9s configure-k9s \
                   configure-dx install-dx configure-dx-ingress

_UNINSTALL_DEPS := uninstall-dx clean-dx \
                   clean-k9s uninstall-k9s \
                   clean-helm uninstall-helm \
                   clean-kubectl uninstall-kubectl \
                   clean-k3d uninstall-k3d

.PHONY: menu check-prereqs analyze-resources start stop \
        install-k3d configure-k3d uninstall-k3d clean-k3d \
        install-kubectl configure-kubectl uninstall-kubectl clean-kubectl \
        install-helm configure-helm uninstall-helm clean-helm \
        install-k9s configure-k9s uninstall-k9s clean-k9s \
        install-all uninstall-all \
        configure-dx install-dx uninstall-dx clean-dx \
        pull-dx-chart pull-dx-values reset-dx-chart patch-dx-chart create-dx-secret \
        pull-search-chart pull-search-values reset-search-chart \
        configure-search-prereqs create-search-certs \
        install-search uninstall-search clean-search \
        resume install-sleep-hook uninstall-sleep-hook \
        load-images check-images

# Auto-create local.env with defaults if it does not exist
$(LOCAL_ENV):
	@bash scripts/init-config.sh

menu: ## Show interactive target menu (default)
	@bash scripts/menu.sh

##@ Pipelines

install-all: $(_INSTALL_DEPS) ## Full install pipeline in dependency order

uninstall-all: $(_UNINSTALL_DEPS) ## Full uninstall pipeline in reverse order

##@ Cluster Lifecycle

start: ## Start the k3d cluster
	k3d cluster start $(CLUSTER_NAME)

stop: ## Stop the k3d cluster and free CPU/RAM
	k3d cluster stop $(CLUSTER_NAME)

##@ Prerequisites

check-prereqs: ## Check for Docker, curl, make; offer to install missing tools
	@bash scripts/check-prereqs.sh

analyze-resources: ## Detect system resources; recommend and save k3d settings to local.env
	@bash scripts/analyze-resources.sh

##@ k3d

install-k3d: ## Download and install the k3d binary
	@bash scripts/install-k3d.sh

configure-k3d: ## Create the k3d cluster from local.env settings
	@CLUSTER_NAME=$(CLUSTER_NAME) bash scripts/configure-k3d.sh

uninstall-k3d: ## Delete the k3d cluster and remove the k3d binary
	@k3d cluster delete $(CLUSTER_NAME) 2>/dev/null || true
	@sudo rm -f /usr/local/bin/k3d
	@echo "k3d cluster deleted and binary removed."

clean-k3d: ## Remove generated k3d cluster config and local image registry
	@rm -f config/k3d-cluster.yaml
	@k3d registry delete dx-registry 2>/dev/null || true
	@echo "Removed k3d cluster config and local registry."

##@ kubectl

install-kubectl: ## Download and install kubectl
	@bash scripts/install-kubectl.sh

configure-kubectl: ## Set kubectl context and install shell completions
	@CLUSTER_NAME=$(CLUSTER_NAME) bash scripts/configure-kubectl.sh

uninstall-kubectl: ## Remove the kubectl binary
	@sudo rm -f /usr/local/bin/kubectl
	@echo "kubectl removed."

clean-kubectl: ## Remove kubectl shell completions
	@sudo rm -f /etc/bash_completion.d/kubectl
	@rm -f $(HOME)/.config/fish/completions/kubectl.fish
	@echo "kubectl completions removed."

##@ Helm

install-helm: ## Download and install Helm
	@bash scripts/install-helm.sh

configure-helm: ## Add Helm repositories and install shell completions
	@bash scripts/configure-helm.sh

uninstall-helm: ## Remove the Helm binary
	@sudo rm -f /usr/local/bin/helm
	@echo "Helm removed."

clean-helm: ## Remove Helm repositories and shell completions
	@helm repo remove bitnami 2>/dev/null || true
	@sudo rm -f /etc/bash_completion.d/helm
	@rm -f $(HOME)/.config/fish/completions/helm.fish
	@echo "Helm repositories and completions removed."

##@ k9s

install-k9s: ## Download and install k9s
	@bash scripts/install-k9s.sh

configure-k9s: ## Write k9s default config and install shell completions
	@bash scripts/configure-k9s.sh

uninstall-k9s: ## Remove the k9s binary
	@sudo rm -f /usr/local/bin/k9s
	@echo "k9s removed."

clean-k9s: ## Remove k9s configuration directory and shell completions
	@rm -rf $(HOME)/.config/k9s
	@sudo rm -f /etc/bash_completion.d/k9s
	@rm -f $(HOME)/.config/fish/completions/k9s.fish
	@echo "k9s configuration removed."

##@ HCL DX

pull-dx-chart: ## Download and extract the HCL DX chart to charts/<version>/ (skips if already present)
	@bash scripts/pull-dx-chart.sh

pull-dx-values: ## Save the HCL DX default values to charts/<version>/dx-values-reference.yaml
	@bash scripts/pull-dx-values.sh

reset-dx-chart: ## Re-extract the HCL DX chart from the local tarball, discarding any edits
	@bash scripts/reset-dx-chart.sh

patch-dx-chart: ## Patch DX chart PVC templates for local-path (ReadWriteMany → ReadWriteOnce)
	@bash scripts/patch-dx-chart.sh

create-dx-secret: ## Create the hclcr.io image pull secret in the DX namespace
	@bash scripts/create-dx-secret.sh

configure-dx: ## Create DX namespace and save deployment settings to local.env
	@bash scripts/configure-dx.sh

configure-dx-ingress: ## Create Traefik TCP passthrough route so DX is reachable at https://localhost
	@bash scripts/configure-dx-ingress.sh

install-dx: ## Install or upgrade HCL DX via Helm (uses local chart if pulled, otherwise OCI)
	@bash scripts/install-dx.sh

open-dx: ## Forward HAProxy to localhost:8443 and open HCL DX in the browser
	@bash scripts/open-dx.sh

uninstall-dx: ## Uninstall the HCL DX Helm release
	@bash scripts/uninstall-dx.sh

clean-dx: ## Delete the DX namespace and remove generated DX files
	@bash scripts/clean-dx.sh

##@ HCL DX Search v2

pull-search-chart: ## Download and extract the DX Search v2 chart to charts/search/<version>/
	@bash scripts/pull-search-chart.sh

pull-search-values: ## Save DX Search v2 default values to charts/search/<version>/search-values-reference.yaml
	@bash scripts/pull-search-values.sh

reset-search-chart: ## Re-extract the DX Search v2 chart from the local tarball, discarding any edits
	@bash scripts/reset-search-chart.sh

configure-search-prereqs: ## Set vm.max_map_count=262144 on the host (required by OpenSearch)
	@bash scripts/configure-search-prereqs.sh

create-search-certs: ## Generate TLS certs for OpenSearch and create the three k8s secrets
	@bash scripts/create-search-certs.sh

install-search: ## Install or upgrade HCL DX Search v2 via Helm (runs prereqs + cert setup automatically)
	@bash scripts/install-search.sh

uninstall-search: ## Uninstall the HCL DX Search v2 Helm release
	@bash scripts/uninstall-search.sh

clean-search: ## Remove generated DX Search v2 files
	@bash scripts/clean-search.sh

##@ Laptop

resume: ## Restart Docker and k3d after laptop sleep (fixes ImagePullBackOff)
	@bash scripts/resume.sh

install-sleep-hook: ## Install systemd hook to auto-restart Docker on every resume
	@bash scripts/install-sleep-hook.sh

uninstall-sleep-hook: ## Remove the systemd Docker-restart sleep hook
	@bash scripts/uninstall-sleep-hook.sh

##@ Local Registry

load-images: ## Pull HCL images for the current chart versions and cache in the local registry
	@bash scripts/load-images.sh

check-images: ## Show which images for the current chart versions are cached locally
	@bash scripts/check-images.sh
