#!/usr/bin/env bash
set -euo pipefail

# Prevent word splitting on spaces; use newline and tab as separators
IFS=$'\n\t'

# Script path
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

for node in flatcar-master1 flatcar-worker1 flatcar-worker2; do
    echo
    echo "========== $node =========="

    vagrant ssh "$node" -c '
        echo "--- Hostname ---"
        hostnamectl --static

        echo "--- OS ---"
        grep -E "^(NAME|VERSION)=" /etc/os-release

        echo "--- Netzwerk ---"
        ip -br -4 addr
        ip route

        echo "--- CPU / RAM ---"
        nproc
        free -h

        echo "--- Swap ---"
        swapon --show

        echo "--- MAC-Adressen ---"
        ip -o link show

        echo "--- Product UUID ---"
        sudo cat /sys/class/dmi/id/product_uuid

        echo "--- Sudo ---"
        sudo -n true && echo "sudo: OK" || echo "sudo: FEHLER"

        echo "--- Container Runtime ---"
        systemctl is-active containerd || true
    '
done

for node in flatcar-master1 flatcar-worker1 flatcar-worker2; do
    echo
    echo "========== $node =========="

    vagrant ssh "$node" -c '
        echo "--- Docker ---"
        systemctl is-active docker || true
        systemctl is-enabled docker || true

        echo "--- Containerd ---"
        systemctl status containerd --no-pager -l

        echo "--- Containerd CRI Plugin ---"
        sudo ctr plugins ls | grep -E "cri|TYPE"

        echo "--- Containerd Konfiguration ---"
        sudo grep -n -A 8 -B 3 "SystemdCgroup" /etc/containerd/config.toml 2>/dev/null || true

        echo "--- CRI Tools ---"
        command -v crictl || true
        command -v ctr || true
    '
done

for vm in flatcar-master1 flatcar-worker1 flatcar-worker2; do
    echo
    echo "========== $vm =========="
    VBoxManage showvminfo "$vm" --machinereadable |
        rg -e '^(nic[1-8]|macaddress[1-8])='
done

for ip in 192.168.56.10 192.168.56.13 192.168.56.14; do
    echo "========== $ip =========="
    ssh -i ../../secrets/ssh/id_ed25519 \
        -o IdentitiesOnly=yes \
        -o StrictHostKeyChecking=accept-new \
        core@"$ip" hostname
done

for node in flatcar-master1 flatcar-worker1 flatcar-worker2; do
    echo "========== $node =========="
    vagrant ssh "$node" -c '
        systemctl show containerd \
          -p ActiveState \
          -p UnitFileState \
          -p TriggeredBy \
          -p WantedBy
        sudo crictl info
    '
done

for ip in 192.168.56.10 192.168.56.13 192.168.56.14; do
    echo "=== $ip ==="
    time ssh \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        core@"$ip" 'echo SSH_OK'
done

for ip in 192.168.56.10 192.168.56.13 192.168.56.14; do
    echo "=== $ip ==="
    ping -c 5 "$ip"
done

for ip in 192.168.56.10 192.168.56.13 192.168.56.14; do
    echo "=== $ip ==="
    ssh -i ../../secrets/ssh/id_ed25519 core@"$ip" '
        echo "Hostname: $(hostname)"
        echo "Cgroup:   $(stat -fc %T /sys/fs/cgroup/)"
        echo "Swap:"
        cat /proc/swaps
    '
done
