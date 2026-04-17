# Ubuntu Packer Build and Vagrant Startup

<img src="https://img.shields.io/badge/Ubuntu-f24e20?logo=ubuntu&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/virtualbox-033467?logo=virtualbox&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/Packer-00affb?logo=packer&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/Vagrant-0e6aec?logo=vagrant&logoColor=white&style=flat" />

---

[Back to home](../../README.md)

---
### Prepare and Run Packer Build

After starting `packer build`, a VirtualBox VM is automatically created and booted using the specified Ubuntu ISO.  
The installation is performed unattended based on the configuration in `http/user-data` (Autoinstall/cloud-init).

During installation, a user with the username/password `vagrant` is created (including SSH access).  
After a successful build, the VM is shut down and exported by Packer.

The export is located in the directory `packer/ubuntu/output-ubuntu`.  
Afterwards, a Vagrant box is automatically created from this export.  
It is stored at `packer/ubuntu/ubuntu-base.box` and serves as the base image for subsequent Vagrant VMs.

### Download Ubuntu Image

```bash
#!/usr/bin/env bash
set -e

BASE_URL="https://releases.ubuntu.com"
LATEST=$(curl -s $BASE_URL/ | grep -oP 'href="\K24\.04\.[0-9]+' | sort -V | tail -1)
ISO_URL="$BASE_URL/$LATEST/ubuntu-$LATEST-desktop-amd64.iso"

[[ -d "${HOME}/vbox/images" ]] || mkdir "${HOME}/vbox/images"
wget -O "${HOME}/vbox/images/ubuntu-${LATEST}-desktop-amd64.iso" "${ISO_URL}"
```

### Add SSH Key Pair to packer/ubuntu/http/user-data

```bash
## Generate SSH key pair without passphrase
##
[[ -d "vagrant/keys" ]] || mkdir "vagrant/keys"
ssh-keygen -o -t ed25519 -f vagrant/keys/id_ed25519 -C'spox@vagrant-dev'
# chmod 0600 vagrant/keys/id_ed25519
# chmod 0644 vagrant/keys/id_ed25519.pub

cat vagrant/keys/id_ed25519.pub
vi packer/ubuntu/http/user-data

## Add SSH key to packer/ubuntu/http/user-data
##
# ssh:
#   install-server: true
#   allow-pw: true
#   authorized-keys:
#     - ssh-ed25519 AAAA...FYlT spox@vagrant-dev
```

### Initialize and Run Packer Build

```bash
cd packer/ubuntu
packer init ubuntu.pkr.hcl
packer build ubuntu.pkr.hcl
```

### Initialize and Start Vagrant Box

```bash
## Ubuntu VM starten
cd ../vagrant/ubuntu
vagrant box add ../../packer/ubuntu/ubuntu-client.box --name ubuntu-client --force
vagrant up
```
