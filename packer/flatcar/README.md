# Flatcar Container Linux Packer Build and Vagrant Startup

<img src="https://img.shields.io/badge/Flatcar%20Container%20Linux-4A90D9?style=flat&logo=linux&labelColor=ffffff&logoColor=4A90D9" /> <img src="https://img.shields.io/badge/Fedora%20Butane-51A2DA?style=flat&logo=fedora&labelColor=ffffff&logoColor=51A2DA" /> <img src="https://img.shields.io/badge/virtualbox-033467?logo=virtualbox&logoColor=white&style=flat" />  <img src="https://img.shields.io/badge/Packer-00affb?logo=packer&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/Vagrant-0e6aec?logo=vagrant&logoColor=white&style=flat" />

---

[Back to home](../../README.md)

---
### Prepare Flatcar Container Linux Packer Build

After running `packer build`, a VirtualBox VM is automatically created and booted using the specified Flatcar Container Linux ISO image.
The installation is performed unattended using the Ignition configuration file `config/ansible_config.ign`, which is generated from the Butane configuration file `config/ansible_config.bu`.
During installation, the users `core` and `hth` are created and configured with SSH access.
After the installation is complete, the VM is shut down and exported by Packer.
The exported VirtualBox image is stored in: `packer/flatcar/flatcar-base.box`

### Generate Ignition Configuration

[Flatcar Container Linux Ignition File](config/README.md)

### Initialize and Run Packer Build

```bash
cd packer/flatcar
packer init flatcar.pkr.hcl
packer validate flatcar.pkr.hcl
packer build flatcar.pkr.hcl

ls -la                    
# flatcar-base.box
```

### Initialize and Start Single Vagrant Box

```bash
## Start Single Flatcar VirtualBox VM
## sudo apt install direnv -y 
cd vagrant/flatcar

vi .envrc
# export VAGRANT_VAGRANTFILE=Vagrantfile_k8s_cluster
export VAGRANT_VAGRANTFILE=Vagrantfile_single_host

direnv allow

vagrant box add ../../packer/flatcar/flatcar-base.box --name flatcar-base --force
vagrant up
```

### Initialize and start multiple Vagrant boxes for a Kubernetes cluster

```bash
## Start multiple Flatcar VirtualBox VMs
cd vagrant/flatcar

vi .envrc
export VAGRANT_VAGRANTFILE=Vagrantfile_k8s_cluster
# export VAGRANT_VAGRANTFILE=Vagrantfile_single_host

direnv allow

vagrant box add ../../packer/flatcar/flatcar-base.box --name flatcar-base --force
vagrant up
```

### Create a Kubernetes cluster

To create a Kubernetes cluster, the following repositories are required.

- [Manage Kubernetes Clusters](https://github.com/hth73/hth-kubernetes)
