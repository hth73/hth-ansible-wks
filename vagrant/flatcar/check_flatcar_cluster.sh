#!/usr/bin/env bash
set -uo pipefail

# Prüft alle laufenden Vagrant-Flatcar-VMs (3 bis 6 Nodes).
# Erwartet pro VM eine Host-only-Adresse im Netz 192.168.56.0/24.
# Das Skript verändert keine Systemeinstellungen. Es prüft insbesondere,
# ob sshd.socket deaktiviert und sshd.service aktiviert/laufend ist.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$SCRIPT_DIR" || exit 1

SSH_USER="${SSH_USER:-core}"
SSH_CHECK_RUNS="${SSH_CHECK_RUNS:-3}"
SSH_CONNECT_TIMEOUT="${SSH_CONNECT_TIMEOUT:-10}"
SSH_KEY="${SSH_KEY:-$SCRIPT_DIR/../../secrets/ssh/id_ed25519}"

FAILURES=0
CHECKS=0

pass() { printf '[PASS] %s\n' "$*"; CHECKS=$((CHECKS + 1)); }
fail() { printf '[FAIL] %s\n' "$*" >&2; CHECKS=$((CHECKS + 1)); FAILURES=$((FAILURES + 1)); }
info() { printf '[INFO] %s\n' "$*"; }

for cmd in vagrant ssh; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        fail "Benötigtes Kommando nicht gefunden: $cmd"
    fi
done
if ! command -v vagrant >/dev/null 2>&1; then
    printf '\nAbbruch: Vagrant ist nicht verfügbar.\n' >&2
    exit 1
fi

SSH_ARGS=(-o BatchMode=yes -o "ConnectTimeout=$SSH_CONNECT_TIMEOUT" -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR)
if [[ -r "$SSH_KEY" ]]; then
    SSH_ARGS+=(-i "$SSH_KEY" -o IdentitiesOnly=yes)
else
    info "SSH-Key nicht unter '$SSH_KEY' gefunden; verwende SSH-Agent/Standard-Identitäten."
fi

printf '\n========== Vagrant-VMs erkennen ==========\n'
# Vagrant liefert pro Maschine eine Zeile: timestamp,machine,state,running|poweroff|...
declare -a NODES=()
declare -A NODE_STATES=()
while IFS=, read -r _timestamp node event state; do
    if [[ "$event" == "state" && -n "$node" ]]; then
        NODES+=("$node")
        NODE_STATES["$node"]="$state"
    fi
done < <(vagrant status --machine-readable 2>/dev/null)

NODE_COUNT=${#NODES[@]}
if (( NODE_COUNT < 3 || NODE_COUNT > 6 )); then
    fail "Erwartet werden 3 bis 6 Vagrant-Maschinen, gefunden: $NODE_COUNT (${NODES[*]:-keine})"
else
    pass "$NODE_COUNT Vagrant-Maschinen gefunden: ${NODES[*]}"
fi

if (( NODE_COUNT == 0 )); then
    printf '\nKeine Vagrant-Maschinen gefunden. Abbruch.\n' >&2
    exit 1
fi

# Ein Remote-Aufruf pro VM: Basisdaten und Sollzustand der Services prüfen.
read -r -d '' REMOTE_CHECK <<'REMOTE' || true
set +e
failures=0

check_unit() {
    unit="$1"
    expected_enabled="$2"
    expected_active="$3"
    actual_enabled="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
    actual_active="$(systemctl is-active "$unit" 2>/dev/null || true)"
    if [[ "$actual_enabled" == "$expected_enabled" && "$actual_active" == "$expected_active" ]]; then
        printf '[PASS] %s enabled=%s active=%s\n' "$unit" "$actual_enabled" "$actual_active"
    else
        printf '[FAIL] %s erwartet enabled=%s active=%s, tatsächlich enabled=%s active=%s\n' \
            "$unit" "$expected_enabled" "$expected_active" "$actual_enabled" "$actual_active"
        failures=$((failures + 1))
    fi
}

printf '%s\n' '--- Hostname / Betriebssystem ---'
hostnamectl --static 2>/dev/null || hostname
sed -n -E '/^(NAME|VERSION)=/p' /etc/os-release

printf '%s\n' '--- Host-only-IP ---'
ip -o -4 addr show | awk '{split($4,a,"/"); if (index(a[1],"192.168.56.")==1) {print "HOSTONLY_IP=" a[1]; found=1; exit}} END {if (!found) print "HOSTONLY_IP="}'

printf '%s\n' '--- Netzwerk ---'
ip -br -4 addr
ip route

printf '%s\n' '--- CPU / RAM ---'
printf 'CPU: '; nproc
free -h

printf '%s\n' '--- Swap ---'
swapon --show
if [[ -z "$(swapon --noheadings 2>/dev/null)" ]]; then
    printf '%s\n' '[PASS] Swap ist deaktiviert'
else
    printf '%s\n' '[FAIL] Swap ist aktiv'
    failures=$((failures + 1))
fi

printf '%s\n' '--- MAC-Adressen / Product UUID ---'
ip -o link show
if [[ -r /sys/class/dmi/id/product_uuid ]]; then
    cat /sys/class/dmi/id/product_uuid
else
    printf '%s\n' '[WARN] Product UUID nicht lesbar'
fi

printf '%s\n' '--- Sudo ---'
if sudo -n true 2>/dev/null; then printf '%s\n' '[PASS] sudo ohne Passwort'; else printf '%s\n' '[FAIL] sudo -n funktioniert nicht'; failures=$((failures + 1)); fi

printf '%s\n' '--- SSH-Dienste (Soll: Socket aus, Daemon an) ---'
check_unit sshd.socket masked inactive
check_unit sshd.service enabled active
if sudo -n ss -lntp 2>/dev/null | awk '$4 ~ /:22$/ {found=1; print} END {exit !found}'; then
    printf '%s\n' '[PASS] TCP-Port 22 lauscht'
else
    printf '%s\n' '[FAIL] Kein Listener auf TCP-Port 22'
    failures=$((failures + 1))
fi

printf '%s\n' '--- Container Runtime ---'
if [[ "$(systemctl is-active containerd 2>/dev/null || true)" == active ]]; then
    printf '%s\n' '[PASS] containerd active'
else
    printf '[FAIL] containerd state=%s\n' "$(systemctl is-active containerd 2>/dev/null || true)"
    failures=$((failures + 1))
fi
systemctl show containerd -p ActiveState -p UnitFileState -p TriggeredBy -p WantedBy

printf '%s\n' '--- Containerd CRI Plugin ---'
if command -v ctr >/dev/null 2>&1; then
    cri_plugins="$(sudo -n ctr plugins ls 2>/dev/null || true)"
    printf '%s\n' "$cri_plugins" | awk 'NR==1 || /cri/'
    if printf '%s\n' "$cri_plugins" | awk '$1=="io.containerd.grpc.v1" && $2=="cri" && $NF=="ok" {found=1} END {exit !found}'; then
        printf '%s\n' '[PASS] containerd CRI-Plugin ist ok'
    else
        printf '%s\n' '[FAIL] containerd CRI-Plugin fehlt oder ist nicht ok'
        failures=$((failures + 1))
    fi
else
    printf '%s\n' '[FAIL] ctr nicht gefunden'
    failures=$((failures + 1))
fi

printf '%s\n' '--- Docker (optional) ---'
printf 'docker active: '; systemctl is-active docker 2>/dev/null || true
printf 'docker enabled: '; systemctl is-enabled docker 2>/dev/null || true

printf '%s\n' '--- Containerd Konfiguration ---'
if [[ -r /etc/containerd/config.toml ]]; then
    awk '/SystemdCgroup/ {print NR ":" $0}' /etc/containerd/config.toml
else
    printf '%s\n' '[INFO] /etc/containerd/config.toml nicht vorhanden oder nicht lesbar'
fi

printf '%s\n' '--- CRI Tools ---'
command -v crictl || true
command -v ctr || true
if command -v crictl >/dev/null 2>&1; then
    if sudo -n crictl info >/dev/null 2>&1; then printf '%s\n' '[PASS] crictl info'; else printf '%s\n' '[FAIL] crictl info'; failures=$((failures + 1)); fi
fi

printf '%s\n' '--- Cgroups ---'
cgroup_type="$(stat -fc %T /sys/fs/cgroup/ 2>/dev/null || true)"
printf 'Cgroup filesystem: %s\n' "$cgroup_type"
if [[ "$cgroup_type" == cgroup2fs ]]; then printf '%s\n' '[PASS] cgroup v2'; else printf '%s\n' '[FAIL] cgroup v2 erwartet'; failures=$((failures + 1)); fi

printf 'REMOTE_CHECK_FAILURES=%s\n' "$failures"
exit "$failures"
REMOTE

# Ergebnisse pro Node sammeln.
declare -A NODE_IPS=()
for node in "${NODES[@]}"; do
    printf '\n========== %s (%s) ==========\n' "$node" "${NODE_STATES[$node]}"
    if [[ "${NODE_STATES[$node]}" != "running" ]]; then
        fail "$node ist nicht running (Status: ${NODE_STATES[$node]})"
        continue
    fi

    remote_output="$(vagrant ssh "$node" -c "$REMOTE_CHECK" 2>&1)"
    remote_rc=$?
    printf '%s\n' "$remote_output"

    ip="$(printf '%s\n' "$remote_output" | sed -n 's/^HOSTONLY_IP=//p' | tail -n 1 | tr -d '\r')"
    if [[ -z "$ip" ]]; then
        fail "$node: keine Host-only-IP im Netz 192.168.56.x gefunden"
    else
        NODE_IPS["$node"]="$ip"
        pass "$node Host-only-IP: $ip"
    fi

    remote_failures="$(printf '%s\n' "$remote_output" | sed -n 's/^REMOTE_CHECK_FAILURES=//p' | tail -n 1 | tr -d '\r')"
    if [[ "$remote_rc" -eq 0 && "$remote_failures" == "0" ]]; then
        pass "$node: Remote-Prüfungen erfolgreich"
    else
        fail "$node: Remote-Prüfungen fehlgeschlagen (Exit-Code $remote_rc, gemeldete Fehler: ${remote_failures:-unbekannt})"
    fi

done

printf '\n========== VirtualBox-Netzwerk ==========\n'
if command -v VBoxManage >/dev/null 2>&1; then
    for node in "${NODES[@]}"; do
        printf '\n--- %s ---\n' "$node"
        if VBoxManage showvminfo "$node" --machinereadable 2>/dev/null | awk -F= '/^(nic[1-8]|macaddress[1-8])=/ {print}' ; then
            :
        else
            info "VirtualBox-Details für $node konnten nicht gelesen werden (VM-Name ggf. abweichend)."
        fi
    done
else
    info 'VBoxManage nicht gefunden; VirtualBox-Prüfung übersprungen.'
fi

printf '\n========== SSH-Verbindung vom Host ==========\n'
for node in "${NODES[@]}"; do
    ip="${NODE_IPS[$node]:-}"
    [[ -n "$ip" ]] || { info "$node: SSH-Test übersprungen (keine IP)."; continue; }
    printf '\n--- %s (%s) ---\n' "$node" "$ip"
    node_ssh_ok=0
    for ((attempt=1; attempt<=SSH_CHECK_RUNS; attempt++)); do
        start_ns="$(date +%s%N)"
        if remote_hostname="$(ssh "${SSH_ARGS[@]}" "$SSH_USER@$ip" 'hostnamectl --static 2>/dev/null || hostname' 2>&1)"; then
            end_ns="$(date +%s%N)"
            elapsed="$(awk -v start="$start_ns" -v end="$end_ns" 'BEGIN {printf "%.3f", (end-start)/1000000000}')"
            printf '[PASS] Versuch %d/%d: %s, %s s\n' "$attempt" "$SSH_CHECK_RUNS" "$remote_hostname" "$elapsed"
            node_ssh_ok=$((node_ssh_ok + 1))
        else
            printf '[FAIL] Versuch %d/%d: %s\n' "$attempt" "$SSH_CHECK_RUNS" "$remote_hostname" >&2
            FAILURES=$((FAILURES + 1))
        fi
        CHECKS=$((CHECKS + 1))
    done
    if (( node_ssh_ok == SSH_CHECK_RUNS )); then
        pass "$node: alle $SSH_CHECK_RUNS SSH-Verbindungen erfolgreich"
    else
        fail "$node: nur $node_ssh_ok von $SSH_CHECK_RUNS SSH-Verbindungen erfolgreich"
    fi

done

printf '\n========== Ping / Host-only-Netz ==========\n'
for node in "${NODES[@]}"; do
    ip="${NODE_IPS[$node]:-}"
    [[ -n "$ip" ]] || continue
    printf '\n--- %s (%s) ---\n' "$node" "$ip"
    if ping -c 3 -W 2 "$ip"; then
        pass "$node: Ping erreichbar"
    else
        fail "$node: Ping fehlgeschlagen"
    fi
done

printf '\n========== Zusammenfassung ==========\n'
printf 'Nodes gefunden: %d\n' "$NODE_COUNT"
printf 'Prüfungen:       %d\n' "$CHECKS"
printf 'Fehler:          %d\n' "$FAILURES"

if (( FAILURES == 0 )); then
    printf '\nERGEBNIS: ALLE PRÜFUNGEN ERFOLGREICH\n'
    exit 0
else
    printf '\nERGEBNIS: PRÜFUNG MIT FEHLERN – siehe [FAIL]-Meldungen\n' >&2
    exit 1
fi
