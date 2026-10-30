
#!/usr/bin/env bash
set -Eeuo pipefail

# Kubernetes homelab lifecycle management
# Fedora CoreOS / Kubespray / Cilium / Vagrant

MASTER="coreos-master1"
WORKERS=("coreos-worker1" "coreos-worker2")

MASTER_IP="192.168.56.10"
WORKER_IPS=("192.168.56.13" "192.168.56.14")

SSH_USER="core"
SSH_OPTS=(-o ConnectTimeout=5 -o BatchMode=yes)

CILIUM_NAMESPACE="kube-system"
CILIUM_DEPLOYMENT="cilium-operator"
CILIUM_LABEL="io.cilium/app=operator"

ORIGINAL_REPLICAS_FILE=".lab-cilium-replicas"

log() {
    printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

ssh_node() {
    local ip="$1"
    shift
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" "$@"
}

wait_ssh_down() {
    local ip="$1"
    local timeout=120
    local elapsed=0
    while (( elapsed < timeout )); do
        if ! ssh_node "$ip" true >/dev/null 2>&1; then
            log "$ip ist heruntergefahren."
            return 0
        fi
        sleep 2
        ((elapsed+=2))
    done
    die "Timeout beim Herunterfahren von $ip"
}

wait_api() {
    local timeout=180
    local elapsed=0
    log "Warte auf Kubernetes API ..."

    until kubectl get nodes >/dev/null 2>&1; do
        sleep 5
        ((elapsed+=5))
        (( elapsed < timeout )) || die "Kubernetes API nicht erreichbar."
    done
}

wait_nodes_ready() {
    local timeout=240
    local elapsed=0
    log "Warte auf drei Ready-Nodes ..."

    while (( elapsed < timeout )); do
        local count
        count=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 ~ /^Ready/ {n++} END {print n+0}')

        if [[ "$count" -eq 3 ]]; then
            return 0
        fi
        sleep 5
        ((elapsed+=5))
    done
    die "Nicht alle drei Nodes sind Ready."
}

down() {
    command -v kubectl >/dev/null || die "kubectl fehlt."
    command -v ssh >/dev/null || die "ssh fehlt."
    command -v jq >/dev/null || die "jq fehlt."

    log "Prüfe Kubernetes Cluster ..."
    kubectl get nodes
    [[ "$(kubectl get nodes --no-headers | wc -l)" -eq 3 ]] ||
        die "Erwartet werden genau drei Nodes."

    # Original replica count sichern
    local replicas
    replicas=$(kubectl -n "$CILIUM_NAMESPACE" get deployment "$CILIUM_DEPLOYMENT" -o jsonpath='{.spec.replicas}')

    echo "$replicas" > "$ORIGINAL_REPLICAS_FILE"

    # Prüfen, ob der Operator auf dem Master läuft
    kubectl -n "$CILIUM_NAMESPACE" get pods -l "$CILIUM_LABEL" -o wide

    local master_operator
    master_operator=$(kubectl -n "$CILIUM_NAMESPACE" get pods \
        -l "$CILIUM_LABEL" -o json |
        jq -r --arg node "$MASTER" \
        '[.items[] | select(.spec.nodeName == $node)
         | select(.status.phase == "Running")] | length')

    [[ "$master_operator" -ge 1 ]] ||
        die "Kein laufender Cilium Operator auf dem Master."

    log "Cordon der Worker-Nodes ..."
    for worker in "${WORKERS[@]}"; do
        kubectl cordon "$worker"
    done

    # Operator auf dem Worker entfernen.
    # Wegen Cordon kann der Ersatz nicht auf den Workern landen.
    for worker in "${WORKERS[@]}"; do
        local pods
        pods=$(kubectl -n "$CILIUM_NAMESPACE" get pods \
            -l "$CILIUM_LABEL" -o json |
            jq -r --arg node "$worker" \
            '.items[] | select(.spec.nodeName == $node) | .metadata.name')

        for pod in $pods; do
            log "Entferne Operator-Pod $pod auf $worker ..."
            kubectl -n "$CILIUM_NAMESPACE" delete pod "$pod"
        done
    done

    log "Warte auf eine Operator-Replica auf dem Master ..."
    local ready=0
    for _ in {1..36}; do
        ready=$(kubectl -n "$CILIUM_NAMESPACE" get pods \
            -l "$CILIUM_LABEL" -o json |
            jq --arg node "$MASTER" \
            '[.items[] | select(.spec.nodeName == $node)
             | select(.status.phase == "Running")
             | select(any(.status.containerStatuses[]?;
                          .ready == true))] | length')

        [[ "$ready" -ge 1 ]] && break
        sleep 5
    done

    [[ "$ready" -ge 1 ]] ||
        die "Cilium Operator konnte nicht auf dem Master bereitgestellt werden."

    kubectl -n "$CILIUM_NAMESPACE" scale deployment "$CILIUM_DEPLOYMENT" --replicas=1
    kubectl -n "$CILIUM_NAMESPACE" rollout status deployment "$CILIUM_DEPLOYMENT" --timeout=120s

    log "Fahre Worker herunter ..."
    for i in "${!WORKERS[@]}"; do
        local worker="${WORKERS[$i]}"
        local ip="${WORKER_IPS[$i]}"

        log "Shutdown $worker ($ip)"
        ssh_node "$ip" sudo systemctl poweroff || true
        wait_ssh_down "$ip"
    done

    log "Fahre Master herunter ..."
    ssh_node "$MASTER_IP" sudo systemctl poweroff || true
    wait_ssh_down "$MASTER_IP"

    log "Cluster vollständig heruntergefahren."
}

cleanup_terminated_pods() {
    log "Bereinige beendete Pods ..."
    kubectl delete pods -A --field-selector=status.phase=Succeeded --ignore-not-found
    kubectl delete pods -A --field-selector=status.phase=Failed --ignore-not-found
}

up() {
    command -v vagrant >/dev/null || die "Vagrant fehlt."
    command -v kubectl >/dev/null || die "kubectl fehlt."

    log "Starte Master ..."
    vagrant up "$MASTER"
    wait_api

    log "Starte Worker ..."
    vagrant up "${WORKERS[@]}"
    wait_nodes_ready

    log "Uncordon aller Nodes ..."
    kubectl uncordon "$MASTER"
    for worker in "${WORKERS[@]}"; do
        kubectl uncordon "$worker"
    done

    local replicas=2
    if [[ -f "$ORIGINAL_REPLICAS_FILE" ]]; then
        replicas=$(cat "$ORIGINAL_REPLICAS_FILE")
    fi

    log "Stelle Cilium Operator Replicas auf $replicas ..."
    kubectl -n "$CILIUM_NAMESPACE" scale deployment "$CILIUM_DEPLOYMENT" --replicas="$replicas"
    kubectl -n "$CILIUM_NAMESPACE" rollout status deployment "$CILIUM_DEPLOYMENT" --timeout=180s
    cleanup_terminated_pods

    log "Cluster gestartet."
    kubectl get nodes
    kubectl get pods -A
}



# Always run Vagrant commands from the directory containing this script.
cd "$(dirname "$0")"

case "${1:-}" in
    down)
        down
        ;;
    up)
        up
        ;;
    *)
        echo "Usage: $0 {down|up}"
        exit 1
        ;;
esac
