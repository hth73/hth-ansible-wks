# Ubuntu Packer Build und Vagrant start

<img src="https://img.shields.io/badge/Ubuntu-f24e20?logo=ubuntu&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/virtualbox-033467?logo=virtualbox&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/Packer-00affb?logo=packer&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/Vagrant-0e6aec?logo=vagrant&logoColor=white&style=flat" />

---

[Back to home](../../README.md)

---
### Packer Build vorbereiten und starten

Nach dem Start von **packer build** wird automatisch eine VirtualBox-VM erstellt und mit dem angegebenen Ubuntu-ISO gebootet. Die Installation erfolgt unbeaufsichtigt anhand der Konfiguration in **http/user-data** (Autoinstall/cloud-init). Während der Installation wird ein Benutzer/Passwort "vagrant" angelegt (inkl. SSH-Zugriff).<br>Nach erfolgreichem Build wird die VM heruntergefahren und von Packer exportiert. Der Export befindet sich im Verzeichnis **packer/ubuntu/output-ubuntu**.<br>Im Anschluss wird aus diesem Export automatisch eine Vagrant-Box erstellt. Diese liegt unter **packer/ubuntu/ubuntu-base.box** und dient als Basis für spätere Vagrant-VMs.

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

### SSH Key Pair in packer/ubuntu/http/user-data hinzufügen

```bash
## SSH Key Pair ohne Passphrase anlegen
##
[[ -d "vagrant/keys" ]] || mkdir "vagrant/keys"
ssh-keygen -o -t ed25519 -f vagrant/keys/id_ed25519 -C'spox@vagrant-dev'
# chmod 0600 vagrant/keys/id_ed25519
# chmod 0644 vagrant/keys/id_ed25519.pub

cat vagrant/keys/id_ed25519.pub
vi packer/ubuntu/http/user-data

## SSH Key in packer/ubuntu/http/user-data hinzufügen
##
# ssh:
#   install-server: true
#   allow-pw: true
#   authorized-keys:
#     - ssh-ed25519 AAAA...FYlT spox@vagrant-dev
```

### Packer build initialisieren und starten

```bash
cd packer/ubuntu
packer init ubuntu.pkr.hcl
packer build ubuntu.pkr.hcl
```

### Vagrant Box initialisieren und starten

```bash
## Ubuntu VM starten
cd ../vagrant/ubuntu
vagrant box add ../../packer/ubuntu/ubuntu-client.box --name ubuntu-client --force
vagrant up
```
