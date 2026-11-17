SHELL := /bin/bash
.DEFAULT_GOAL := help

.NOTPARALLEL:

# --------------------------------------------------
# Paths (alles relativ zum Repo-Root, hier "make" starten)
# --------------------------------------------------
REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

KUBEONE_DIR := $(REPO_ROOT)/inventory/kubeone
KUBEONE_MANIFEST := $(KUBEONE_DIR)/kubeone.yaml
HELM_DIR := $(KUBEONE_DIR)/helm
HELM_VALUES := $(HELM_DIR)/values
HELM_CONFIGS := $(HELM_DIR)/configs

# KubeOne schreibt die Kubeconfig als <cluster-name>-kubeconfig ins
# Arbeitsverzeichnis (inventory/kubeone).
KUBECONFIG_FILE := $(KUBEONE_DIR)/kubernetes-kubeconfig
export KUBECONFIG := $(KUBECONFIG_FILE)

# --------------------------------------------------
# Versions
# --------------------------------------------------
# Cilium-Version steht in inventory/kubeone/kubeone.yaml (helmReleases)
CERT_MANAGER_VERSION ?= v1.21.3
METALLB_VERSION ?= 0.16.2
TRAEFIK_VERSION ?= 42.4.0

# Optionale KubeOne-Flags, z. B. KUBEONE_FLAGS="--verbose --debug"
KUBEONE_FLAGS ?=

# --------------------------------------------------
# Targets
# --------------------------------------------------
.PHONY: help bootstrap platform verify cluster

help:
	@echo "KubeOne / Flatcar Kubernetes Lab (aus dem Repo-Root starten)"
	@echo
	@echo "Targets:"
	@echo "  make bootstrap   Kubernetes + Cilium mit KubeOne installieren"
	@echo "  make platform    cert-manager, MetalLB, Traefik + Konfiguration"
	@echo "  make verify      Cluster-Zustand pruefen"
	@echo "  make cluster     bootstrap + platform + verify"
	@echo
	@echo "Optionale Variablen:"
	@echo "  KUBEONE_FLAGS=\"--verbose --debug\""
	@echo "  CERT_MANAGER_VERSION=$(CERT_MANAGER_VERSION)"
	@echo "  METALLB_VERSION=$(METALLB_VERSION)"
	@echo "  TRAEFIK_VERSION=$(TRAEFIK_VERSION)"

# --------------------------------------------------
# KubeOne: Kubernetes + Cilium
# --------------------------------------------------
# KubeOne muss in inventory/kubeone laufen: chart- und valuesFile-Pfade in
# kubeone.yaml sind relativ zum Arbeitsverzeichnis.
bootstrap:
	cd "$(KUBEONE_DIR)" && \
		kubeone apply $(KUBEONE_FLAGS) --manifest "$(KUBEONE_MANIFEST)"
	@test -s "$(KUBECONFIG_FILE)" || { \
		echo "[ERROR] KubeOne kubeconfig was not generated."; exit 1; \
	}
	chmod 600 "$(KUBECONFIG_FILE)"

# --------------------------------------------------
# Platform (nach KubeOne, wenn alle Nodes Ready sind)
# --------------------------------------------------
# KubeOne wendet eigene Addons vor den helmReleases und vor dem Worker-Join
# an. Charts mit CRDs bzw. Pods, die Worker brauchen, laufen deshalb hier.
platform:
	@test -s "$(KUBECONFIG_FILE)" || { \
		echo "[ERROR] Run 'make bootstrap' first."; exit 1; \
	}
	kubectl wait --for=condition=Ready nodes --all --timeout=300s
	helm repo add jetstack https://charts.jetstack.io --force-update
	helm repo add metallb https://metallb.github.io/metallb --force-update
	helm repo add traefik https://traefik.github.io/charts --force-update
	helm repo update jetstack metallb traefik
	helm upgrade --install cert-manager jetstack/cert-manager \
		--namespace cert-manager --create-namespace \
		--version "$(CERT_MANAGER_VERSION)" \
		--values "$(HELM_VALUES)/cert-manager.yaml" \
		--wait --timeout 10m
	helm upgrade --install metallb metallb/metallb \
		--namespace metallb-system --create-namespace \
		--version "$(METALLB_VERSION)" \
		--wait --timeout 10m 
	kubectl apply -f "$(HELM_CONFIGS)/cert-manager/"
	kubectl apply -f "$(HELM_CONFIGS)/metallb/"
	helm upgrade --install traefik traefik/traefik \
		--namespace traefik --create-namespace \
		--version "$(TRAEFIK_VERSION)" \
		--values "$(HELM_VALUES)/traefik.yaml" \
		--wait --timeout 10m

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
	kubectl rollout status daemonset/cilium \
		-n kube-system --timeout=300s
	kubectl -n kube-system exec ds/cilium -c cilium-agent -- \
		cilium-dbg status --brief
	kubectl get ciliumnodeconfigs -n kube-system
	kubectl get ciliumpodippools
	kubectl get nodes -o wide
	kubectl get pods -A -o wide

# --------------------------------------------------
# Complete cluster
# --------------------------------------------------
cluster: bootstrap platform verify
