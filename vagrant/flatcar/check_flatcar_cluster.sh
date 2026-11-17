#!/usr/bin/env bash
set -uo pipefail

# Prüft alle Vagrant-Flatcar-VMs (3 bis 6 Nodes) vor der KubeOne-Installation.
# Erwartet pro VM eine feste Adresse im Bridged-LAN 192.168.178.0/24 auf enp0s8.
# Das Skript verändert keine Systemeinstellungen. Es prüft u. a. Hostname,
# Netzwerk, SSH-Dienste, containerd, cgroup v2, WireGuard und die Erreichbarkeit
# der Nodes untereinander.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$SCRIPT_DIR" || exit 1

SSH_USER="${SSH_USER:-core}"
SSH_CHECK_RUNS="${SSH_CHECK_RUNS:-3}"
SSH_CONNECT_TIMEOUT="${SSH_CONNECT_TIMEOUT:-10}"
SSH_KEY="${SSH_KEY:-$SCRIPT_DIR/../../secrets/ssh/id_ed25519}"

# direnv greift in Skripten nicht -> Vagrantfile explizit setzen
export VAGRANT_VAGRANTFILE="${VAGRANT_VAGRANTFILE:-Vagrantfile_k8s_cluster}"

# Cluster-Netz (Bridged) und Interface, auf dem KubeOne/Cilium arbeiten
NODE_IF="${NODE_IF:-enp0s8}"
NODE_NET_PREFIX="${NODE_NET_PREFIX:-192.168.178.}"

# Soll-IPs je Node (wie im Vagrantfile / kubeone.yaml)
declare -A EXPECTED_IPS=(
    [flatcar-master1]=192.168.178.210
    [flatcar-master2]=192.168.178.211
    [flatcar-master3]=192.168.178.212
    [flatcar-worker1]=192.168.178.213
    [flatcar-worker2]=192.168.178.214
    [flatcar-worker3]=192.168.178.215
)

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

printf '\n========== Vagrant-VMs erkennen (%s) ==========\n' "$VAGRANT_VAGRANTFILE"
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
# NODE_IF wird vor dem Heredoc gesetzt, da dieser nicht expandiert wird.
read -r -d '' REMOTE_CHECK <<'REMOTE' || true
set +e
failures=0
NODE_IF="${NODE_IF:-enp0s8}"

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
printf 'NODE_HOSTNAME=%s\n' "$(hostnamectl --static 2>/dev/null || hostname)"
sed -n -E '/^(NAME|VERSION)=/p' /etc/os-release
printf 'Kernel: %s\n' "$(uname -r)"

printf '%s\n' "--- Cluster-IP auf $NODE_IF ---"
printf 'NODE_IP=%s\n' "$(ip -o -4 addr show dev "$NODE_IF" 2>/dev/null | awk '{split($4,a,"/"); print a[1]; exit}')"
printf 'NODE_MAC=%s\n' "$(cat /sys/class/net/"$NODE_IF"/address 2>/dev/null)"
if [[ "$(cat /sys/class/net/"$NODE_IF"/operstate 2>/dev/null)" == up ]]; then
    printf '[PASS] %s ist up\n' "$NODE_IF"
else
    printf '[FAIL] %s ist nicht up\n' "$NODE_IF"
    failures=$((failures + 1))
fi

printf '%s\n' '--- Netzwerk ---'
ip -br -4 addr
ip route
default_if="$(ip -4 route show default | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"
printf '[INFO] Default-Route ueber: %s (Cilium egressMasqueradeInterfaces erwartet enp0s3)\n' "${default_if:-keine}"

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

printf '%s\n' '--- Product UUID / Machine ID (muessen je Node eindeutig sein) ---'
printf 'PRODUCT_UUID=%s\n' "$(sudo -n cat /sys/class/dmi/id/product_uuid 2>/dev/null)"
printf 'MACHINE_ID=%s\n' "$(cat /etc/machine-id 2>/dev/null)"

printf '%s\n' '--- Zeit-Synchronisation ---'
if [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" == yes ]]; then
    printf '%s\n' '[PASS] Zeit ist synchronisiert'
else
    printf '%s\n' '[FAIL] Zeit ist nicht synchronisiert (Zertifikate/etcd!)'
    failures=$((failures + 1))
fi

printf '%s\n' '--- WireGuard (Cilium-Verschluesselung) ---'
if lsmod | grep -q '^wireguard' || modinfo wireguard >/dev/null 2>&1; then
    printf '%s\n' '[PASS] WireGuard-Kernelmodul verfuegbar'
else
    printf '%s\n' '[FAIL] WireGuard-Kernelmodul nicht verfuegbar'
    failures=$((failures + 1))
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
declare -A NODE_IPS=() NODE_MACS=() NODE_UUIDS=() NODE_MIDS=()
for node in "${NODES[@]}"; do
    printf '\n========== %s (%s) ==========\n' "$node" "${NODE_STATES[$node]}"
    if [[ "${NODE_STATES[$node]}" != "running" ]]; then
        fail "$node ist nicht running (Status: ${NODE_STATES[$node]})"
        continue
    fi

    remote_output="$(vagrant ssh "$node" -c "NODE_IF=$NODE_IF; $REMOTE_CHECK" 2>&1)"
    remote_rc=$?
    printf '%s\n' "$remote_output"

    field() { printf '%s\n' "$remote_output" | sed -n "s/^$1=//p" | tail -n 1 | tr -d '\r'; }

    remote_hostname="$(field NODE_HOSTNAME)"
    if [[ "$remote_hostname" == "$node" ]]; then
        pass "$node: Hostname passt"
    else
        fail "$node: Hostname ist '$remote_hostname' (CiliumNodeConfig matcht auf kubernetes.io/hostname=$node)"
    fi

    ip="$(field NODE_IP)"
    expected="${EXPECTED_IPS[$node]:-}"
    if [[ -z "$ip" ]]; then
        fail "$node: keine IPv4-Adresse auf $NODE_IF"
    elif [[ "$ip" != "$NODE_NET_PREFIX"* ]]; then
        fail "$node: $NODE_IF hat $ip, erwartet Netz ${NODE_NET_PREFIX}x"
    elif [[ -n "$expected" && "$ip" != "$expected" ]]; then
        fail "$node: $NODE_IF hat $ip, erwartet $expected"
        NODE_IPS["$node"]="$ip"
    else
        NODE_IPS["$node"]="$ip"
        pass "$node: $NODE_IF-IP $ip"
    fi

    NODE_MACS["$node"]="$(field NODE_MAC)"
    NODE_UUIDS["$node"]="$(field PRODUCT_UUID)"
    NODE_MIDS["$node"]="$(field MACHINE_ID)"

    remote_failures="$(printf '%s\n' "$remote_output" | sed -n 's/^REMOTE_CHECK_FAILURES=//p' | tail -n 1 | tr -d '\r')"
    if [[ "$remote_rc" -eq 0 && "$remote_failures" == "0" ]]; then
        pass "$node: Remote-Prüfungen erfolgreich"
    else
        fail "$node: Remote-Prüfungen fehlgeschlagen (Exit-Code $remote_rc, gemeldete Fehler: ${remote_failures:-unbekannt})"
    fi

done

printf '\n========== Eindeutigkeit (MAC / Product UUID / Machine ID) ==========\n'
check_unique() {
    local label="$1"; shift
    local -n values="$1"
    local dups
    dups="$(for n in "${!values[@]}"; do [[ -n "${values[$n]}" ]] && printf '%s\n' "${values[$n]}"; done | sort | uniq -d)"
    if [[ -z "$dups" ]]; then
        pass "$label eindeutig"
    else
        fail "$label doppelt vergeben: $(echo $dups)"
    fi
}
check_unique "MAC auf $NODE_IF" NODE_MACS
check_unique "Product UUID" NODE_UUIDS
check_unique "Machine ID" NODE_MIDS

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

printf '\n========== Ping vom Host (%s) ==========\n' "$NODE_IF"
for node in "${NODES[@]}"; do
    ip="${NODE_IPS[$node]:-}"
    [[ -n "$ip" ]] || continue
    if ping -c 3 -W 2 "$ip" >/dev/null; then
        pass "$node ($ip): Ping vom Host erreichbar"
    else
        fail "$node ($ip): Ping vom Host fehlgeschlagen"
    fi
done

printf '\n========== Ping zwischen den Nodes (%s) ==========\n' "$NODE_IF"
# Wichtig fuer Native Routing: jeder Node muss jeden anderen direkt ueber
# das Bridged-LAN erreichen.
for src in "${NODES[@]}"; do
    src_ip="${NODE_IPS[$src]:-}"
    [[ -n "$src_ip" ]] || continue
    for dst in "${NODES[@]}"; do
        [[ "$src" == "$dst" ]] && continue
        dst_ip="${NODE_IPS[$dst]:-}"
        [[ -n "$dst_ip" ]] || continue
        if ssh "${SSH_ARGS[@]}" "$SSH_USER@$src_ip" "ping -c 2 -W 2 -I $NODE_IF $dst_ip >/dev/null" 2>/dev/null; then
            pass "$src -> $dst ($dst_ip)"
        else
            fail "$src -> $dst ($dst_ip) nicht erreichbar"
        fi
    done
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
