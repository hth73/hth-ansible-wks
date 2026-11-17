#!/usr/bin/env bash
set -Eeuo pipefail

# Kubernetes-Homelab sauber herunterfahren und wieder starten.
# Flatcar / KubeOne / Cilium / Vagrant (Bridged LAN)
#
#   ./lab-cluster.sh down     Nodes cordonen, Worker und danach Master herunterfahren
#   ./lab-cluster.sh up       Master starten, Worker starten, Nodes uncordonen
#   ./lab-cluster.sh status   VM- und Node-Status anzeigen

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"

MASTER="flatcar-master1"
WORKERS=("flatcar-worker1" "flatcar-worker2")

MASTER_IP="192.168.178.210"
WORKER_IPS=("192.168.178.213" "192.168.178.214")

SSH_USER="${SSH_USER:-core}"
SSH_KEY="${SSH_KEY:-$REPO_ROOT/secrets/ssh/id_ed25519}"
SSH_OPTS=(-o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR)
[[ -r "$SSH_KEY" ]] && SSH_OPTS+=(-i "$SSH_KEY" -o IdentitiesOnly=yes)

# direnv greift in Skripten nicht -> Vagrantfile und Kubeconfig explizit setzen
export VAGRANT_VAGRANTFILE="${VAGRANT_VAGRANTFILE:-Vagrantfile_k8s_cluster}"
export KUBECONFIG="${KUBECONFIG:-$REPO_ROOT/inventory/kubeone/kubernetes-kubeconfig}"

ALL_NODES=("$MASTER" "${WORKERS[@]}")
NODE_COUNT=${#ALL_NODES[@]}

log() { printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

require() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || die "$cmd fehlt."
    done
}

ssh_node() {
    local ip="$1"; shift
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" "$@"
}

# VirtualBox-Status einer VM laut Vagrant (running, poweroff, aborted, ...)
vm_state() {
    vagrant status "$1" --machine-readable 2>/dev/null |
        awk -F, '$3 == "state" {print $4}' | tail -n 1
}

wait_vm_poweroff() {
    local name="$1" timeout=180 elapsed=0
    while (( elapsed < timeout )); do
        if [[ "$(vm_state "$name")" == "poweroff" ]]; then
            log "$name ist ausgeschaltet."
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    die "Timeout beim Herunterfahren von $name (Status: $(vm_state "$name"))"
}

shutdown_node() {
    local name="$1" ip="$2"
    if [[ "$(vm_state "$name")" != "running" ]]; then
        log "$name laeuft nicht ($(vm_state "$name")), uebersprungen."
        return 0
    fi
    log "Shutdown $name ($ip) ..."
    # Die SSH-Verbindung bricht beim Poweroff ab -> Fehler ignorieren
    ssh_node "$ip" sudo systemctl poweroff || true
    wait_vm_poweroff "$name"
}

wait_api() {
    local timeout=300 elapsed=0
    log "Warte auf Kubernetes API ..."
    until kubectl get --raw=/readyz >/dev/null 2>&1; do
        sleep 5
        elapsed=$((elapsed + 5))
        (( elapsed < timeout )) || die "Kubernetes API nicht erreichbar."
    done
}

wait_nodes_ready() {
    local timeout=300 elapsed=0 count
    log "Warte auf $NODE_COUNT Ready-Nodes ..."
    while (( elapsed < timeout )); do
        count=$(kubectl get nodes --no-headers 2>/dev/null |
            awk '$2 ~ /^Ready/ {n++} END {print n+0}')
        (( count == NODE_COUNT )) && return 0
        sleep 5
        elapsed=$((elapsed + 5))
    done
    kubectl get nodes || true
    die "Nicht alle $NODE_COUNT Nodes sind Ready."
}

cleanup_terminated_pods() {
    log "Bereinige beendete Pods ..."
    kubectl delete pods -A --field-selector=status.phase=Succeeded --ignore-not-found
    kubectl delete pods -A --field-selector=status.phase=Failed --ignore-not-found
}

down() {
    require vagrant kubectl ssh
    [[ -s "$KUBECONFIG" ]] || die "Kubeconfig nicht gefunden: $KUBECONFIG"

    log "Pruefe Kubernetes Cluster ..."
    kubectl get nodes

    # Cordon verhindert, dass Pods waehrend des Herunterfahrens auf
    # gerade noch laufende Nodes umgeplant werden.
    log "Cordon aller Nodes ..."
    local node
    for node in "${ALL_NODES[@]}"; do
        kubectl cordon "$node"
    done

    log "Fahre Worker herunter ..."
    local i
    for i in "${!WORKERS[@]}"; do
        shutdown_node "${WORKERS[$i]}" "${WORKER_IPS[$i]}"
    done

    log "Fahre Master herunter ..."
    shutdown_node "$MASTER" "$MASTER_IP"

    log "Cluster vollstaendig heruntergefahren."
}

up() {
    require vagrant kubectl
    [[ -s "$KUBECONFIG" ]] || die "Kubeconfig nicht gefunden: $KUBECONFIG"

    # --no-provision: die Netzwerk-Provisionierung laeuft nur beim ersten "vagrant up"
    log "Starte Master ..."
    vagrant up --no-provision "$MASTER"
    wait_api

    log "Starte Worker ..."
    vagrant up --no-provision "${WORKERS[@]}"
    wait_nodes_ready

    log "Uncordon aller Nodes ..."
    local node
    for node in "${ALL_NODES[@]}"; do
        kubectl uncordon "$node"
    done

    log "Warte auf Cilium ..."
    kubectl -n kube-system rollout status daemonset/cilium --timeout=300s
    kubectl -n kube-system rollout status deployment/cilium-operator --timeout=300s
    kubectl -n kube-system rollout status deployment/coredns --timeout=300s

    cleanup_terminated_pods

    log "Cluster gestartet."
    kubectl get nodes -o wide
    kubectl get pods -A -o wide
}

status() {
    require vagrant kubectl
    vagrant status
    if kubectl get --raw=/readyz >/dev/null 2>&1; then
        kubectl get nodes -o wide
    else
        log "Kubernetes API nicht erreichbar."
    fi
}

# Vagrant-Befehle immer im Verzeichnis dieses Skripts ausfuehren.
cd "$SCRIPT_DIR"

case "${1:-}" in
    down)   down ;;
    up)     up ;;
    status) status ;;
    *)
        echo "Usage: $0 {down|up|status}"
        exit 1
        ;;
esac
