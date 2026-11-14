SHELL := /bin/bash
.DEFAULT_GOAL := help

.NOTPARALLEL:

# --------------------------------------------------
# Paths
# --------------------------------------------------
KUBEONE_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(KUBEONE_DIR)/..)

VAGRANT_DIR := $(REPO_ROOT)/vagrant/flatcar
VAGRANTFILE := Vagrantfile_k8s_cluster

K8S_REPO ?= $(abspath $(REPO_ROOT)/../hth-kubernetes)
CILIUM_VALUES := $(K8S_REPO)/infrastructure/cilium/values_native.yaml

SSH_KEY := $(REPO_ROOT)/secrets/ssh/id_ed25519

KUBECONFIG_FILE := $(KUBEONE_DIR)/kubernetes-kubeconfig
export KUBECONFIG := $(KUBECONFIG_FILE)

# --------------------------------------------------
# Versions
# --------------------------------------------------
# KubeOne 1.15.0 ships with Cilium 1.20.4
CILIUM_VERSION ?= 1.20.4

# Optional KubeOne flags, e.g. KUBEONE_FLAGS=--debug
KUBEONE_FLAGS ?=

# --------------------------------------------------
# Targets
# --------------------------------------------------
.PHONY: help all up destroy preflight check-vms bootstrap \
        cilium-config verify cluster

help:
	@echo "KubeOne / Flatcar Kubernetes Lab"
	@echo
	@echo "Available targets:"
	@echo "  make up             Start Flatcar VMs"
	@echo "  make destroy        Destroy Flatcar VMs"
	@echo "  make check-vms      Run Flatcar diagnostics"
	@echo "  make preflight      Check SSH, sudo and local tools"
	@echo "  make bootstrap      Install Kubernetes with KubeOne"
	@echo "  make cilium-config  Apply custom Cilium Helm values"
	@echo "  make verify         Verify cluster health"
	@echo "  make cluster        Bootstrap, configure Cilium and verify"
	@echo "  make all            Start VMs and build the complete cluster"
	@echo
	@echo "Optional variables:"
	@echo "  K8S_REPO=/path/to/hth-kubernetes"
	@echo "  CILIUM_VERSION=1.20.4"
	@echo "  KUBEONE_FLAGS=--debug"

# --------------------------------------------------
# Vagrant
# --------------------------------------------------
up:
	cd "$(VAGRANT_DIR)" && \
		VAGRANT_VAGRANTFILE="$(VAGRANTFILE)" vagrant up

destroy:
	cd "$(VAGRANT_DIR)" && \
		VAGRANT_VAGRANTFILE="$(VAGRANTFILE)" vagrant destroy -f
	rm -f "$(KUBECONFIG_FILE)"

# --------------------------------------------------
# Flatcar diagnostics
# --------------------------------------------------
check-vms:
	cd "$(VAGRANT_DIR)" && \
		VAGRANT_VAGRANTFILE="$(VAGRANTFILE)" \
		bash ./check_flatcar_cluster.sh

# --------------------------------------------------
# Preflight
# --------------------------------------------------
preflight:
	@set -e; \
	echo "Checking local tools..."; \
	for cmd in vagrant VBoxManage ssh ssh-add kubeone kubectl helm; do \
		command -v "$$cmd" >/dev/null 2>&1 || { \
			echo "[ERROR] Missing command: $$cmd"; exit 1; \
		}; \
	done; \
	test -f "$(KUBEONE_DIR)/kubeone.yaml"; \
	test -f "$(SSH_KEY)"; \
	test -f "$(CILIUM_VALUES)"; \
	echo "Loading SSH key into agent..."; \
	ssh-add "$(SSH_KEY)"; \
	echo "Checking SSH and sudo on all nodes..."; \
	for ip in 192.168.56.10 192.168.56.13 192.168.56.14; do \
		echo "=== $$ip ==="; \
		ssh -o BatchMode=yes \
		    -o ConnectTimeout=10 \
		    -o StrictHostKeyChecking=accept-new \
		    core@"$$ip" 'sudo -n true' || exit 1; \
	done; \
	echo "Preflight successful."

# --------------------------------------------------
# KubeOne
# --------------------------------------------------
bootstrap: preflight
	cd "$(KUBEONE_DIR)" && \
		kubeone apply $(KUBEONE_FLAGS) --manifest kubeone.yaml
	@test -s "$(KUBECONFIG_FILE)" || { \
		echo "[ERROR] KubeOne kubeconfig was not generated."; exit 1; \
	}
	chmod 600 "$(KUBECONFIG_FILE)"

# --------------------------------------------------
# Cilium
# --------------------------------------------------
cilium-config:
	@test -s "$(KUBECONFIG_FILE)" || { \
		echo "[ERROR] Run 'make bootstrap' first."; exit 1; \
	}
	@test -f "$(CILIUM_VALUES)" || { \
		echo "[ERROR] Cilium values file not found: $(CILIUM_VALUES)"; exit 1; \
	}
	@echo "Checking KubeOne Cilium installation..."
	@helm status cilium --namespace kube-system >/dev/null
	helm repo add cilium https://helm.cilium.io/ --force-update
	helm repo update cilium
	helm upgrade cilium cilium/cilium \
		--namespace kube-system \
		--version "$(CILIUM_VERSION)" \
		--reuse-values \
		--values "$(CILIUM_VALUES)" \
		--wait \
		--timeout 10m
	kubectl rollout status daemonset/cilium \
		-n kube-system --timeout=600s
	kubectl rollout status deployment/cilium-operator \
		-n kube-system --timeout=600s
	kubectl rollout status deployment/hubble-relay \
		-n kube-system --timeout=600s
	kubectl rollout status deployment/hubble-ui \
		-n kube-system --timeout=600s

# --------------------------------------------------
# Verification
# --------------------------------------------------
verify:
	@test -s "$(KUBECONFIG_FILE)" || { \
		echo "[ERROR] Kubeconfig not found."; exit 1; \
	}
	kubectl wait --for=condition=Ready nodes --all --timeout=300s
	kubectl rollout status deployment/coredns \
		-n kube-system --timeout=300s
	kubectl get nodes -o wide
	kubectl get pods -A -o wide

# --------------------------------------------------
# Complete cluster
# --------------------------------------------------
cluster: bootstrap cilium-config verify

all: up cluster
