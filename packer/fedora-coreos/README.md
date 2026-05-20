# Fedora CoreOS Packer Build and Vagrant Startup

<img src="https://img.shields.io/badge/Fedora%20CoreOS-51A2DA?style=flat&logo=fedora&labelColor=ffffff&logoColor=51A2DA" /> <img src="https://img.shields.io/badge/Fedora%20Butane-51A2DA?style=flat&logo=fedora&labelColor=ffffff&logoColor=51A2DA" /> <img src="https://img.shields.io/badge/virtualbox-033467?logo=virtualbox&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/Packer-00affb?logo=packer&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/Vagrant-0e6aec?logo=vagrant&logoColor=white&style=flat" />

---

[Back to home](../../README.md)

---
### Prepare Fedora CoreOS Packer Build

After running `packer build`, a VirtualBox VM is automatically created and booted using the specified Fedora CoreOS ISO image.
The installation is performed unattended using the Ignition configuration file `config/ansible_config.ign`, which is generated from the Butane configuration file `config/ansible_config.bu`.
During installation, the users `core` and `hth` are created and configured with SSH access.
After the installation is complete, the VM is shut down and exported by Packer.
The exported VirtualBox image is stored in: `packer/fedora-coreos/fedora-coreos-base.box`

### Generate Ignition Configuration

[CoreOS Ignition File](config/README.md)


### Initialize and Run Packer Build

```bash
cd packer/fedora-coreos
packer init fedora-coreos.pkr.hcl
packer validate fedora-coreos.pkr.hcl
packer build fedora-coreos.pkr.hcl
```

### Initialize and Start Vagrant Box

```bash
## Ubuntu VM starten
cd ../vagrant/fedora-coreos
vagrant box add ../../packer/fedora-coreos/fedora-coreos-base.box --name fedora-coreos-client --force
vagrant up
```
