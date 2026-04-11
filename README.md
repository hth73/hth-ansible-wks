# Ubuntu/Manjaro Linux Unattended Installation mit Packer, Vagrant und Ansible

<img src="https://img.shields.io/badge/Ubuntu-f24e20?logo=ubuntu&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/Manjaro-00bfa5?logo=manjaro&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/virtualbox-033467?logo=virtualbox&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/Packer-00affb?logo=packer&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/Ansible-d5000e?logo=ansible&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/Vagrant-0e6aec?logo=vagrant&logoColor=white&style=flat" />

---
## Beschreibung

Dieses kleine Projekt automatisiert mir meine Ubuntu- und (zukünftig) Manjaro-Desktop-VMs in VirtualBox.<br>
Ziel ist es, schnell reproduzierbare Linux-Testmaschinen bereitzustellen, ohne manuelle Installation und Konfiguration.

Der Aufbau erfolgt in drei Schritten:
1. **Packer (Image Build)**
   - Verwendet ein Ubuntu/Manjaro ISO (lokal oder remote)
   - Führt eine unbeaufsichtigte Installation (autoinstall/cloud-init) durch
   - Erstellt daraus ein minimales, wiederverwendbares Vagrant Base Image
2. **Vagrant (VM Lifecycle)**
   - Startet eine VM basierend auf dem erzeugten Base Image
   - Kümmert sich um Netzwerk, Ressourcen und SSH-Zugriff
   - Stellt eine reproduzierbare Laufzeitumgebung bereit
3. **Ansible (Provisioning)**
   - Konfiguriert die VM nach dem Start
   - Installiert Pakete und Anwendungen
   - Wendet systemweite Konfigurationen über Rollen an (z. B. base, apps, desktop)

---

### SSH Key Pair für Vagrant anlegen

```bash
## SSH Key Pair ohne Passphrase anlegen
##
[[ -d "vagrant/keys" ]] || mkdir "vagrant/keys"
ssh-keygen -o -t ed25519 -f vagrant/keys/id_ed25519 -C'spox@vagrant-dev'
# chmod 0600 vagrant/keys/id_ed25519
# chmod 0644 vagrant/keys/id_ed25519.pub

cat vagrant/keys/id_ed25519.pub
vi packer/ubuntu/http/user-data

# ssh:
#   install-server: true
#   allow-pw: true
#   authorized-keys:
#     - ssh-ed25519 AAAA...FYlT spox@vagrant-dev
```

### Ubuntu Image download

```bash
#!/usr/bin/env bash
set -e

BASE_URL="https://releases.ubuntu.com"
LATEST=$(curl -s $BASE_URL/ | grep -oP 'href="\K24\.04\.[0-9]+' | sort -V | tail -1)
ISO_URL="$BASE_URL/$LATEST/ubuntu-$LATEST-desktop-amd64.iso"

[[ -d "${HOME}/vbox/images" ]] || mkdir "${HOME}/vbox/images"
wget -O "${HOME}/vbox/images/ubuntu-${LATEST}-desktop-amd64.iso" "${ISO_URL}"
```

### Packer Build starten

Nach dem Start von **packer build** wird automatisch eine VirtualBox-VM erstellt und mit dem angegebenen Ubuntu-ISO gebootet. Die Installation erfolgt unbeaufsichtigt anhand der Konfiguration in **http/user-data** (Autoinstall/cloud-init). Während der Installation wird ein Benutzer/Passwort "vagrant" angelegt (inkl. SSH-Zugriff).<br>Nach erfolgreichem Build wird die VM heruntergefahren und von Packer exportiert. Der Export befindet sich im Verzeichnis **packer/ubuntu/output-ubuntu**.<br>Im Anschluss wird aus diesem Export automatisch eine Vagrant-Box erstellt. Diese liegt unter **packer/ubuntu/ubuntu-base.box** und dient als Basis für spätere Vagrant-VMs.

```bash
cd packer/ubuntu
packer init ubuntu.pkr.hcl
packer build ubuntu.pkr.hcl
```

### Vagrant VM starten

```bash
cd ../vagrant
vagrant box add ../packer/ubuntu/ubuntu-client.box --name ubuntu-client --force
vagrant up
```
