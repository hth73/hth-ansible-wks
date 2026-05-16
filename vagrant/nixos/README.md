# NixOS Vagrant Startup

<img src="https://img.shields.io/badge/virtualbox-033467?logo=virtualbox&logoColor=white&style=flat" />  <img src="https://img.shields.io/badge/Vagrant-0e6aec?logo=vagrant&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/NixOS-5277C3?style=flat&logo=nixos&labelColor=ffffff&logoColor=5277C3" /> <img src="https://img.shields.io/badge/NixOS%20Flakes-5277C3?style=flat&logo=nixos&labelColor=ffffff&logoColor=5277C3" />

---

[Back to home](../../README.md)

---

## Building a NixOS Base Image for Vagrant

Unfortunately, NixOS does not provide a built-in unattended installation mechanism comparable to Debian Preseed, Red Hat Kickstart, or Ubuntu Cloud-Init that can be used directly with Packer to create a fully automated base image from scratch.

The recommended NixOS installation approach uses nixos-anywhere, which requires an already running temporary system with:

- Root or sudo privileges
- Network connectivity
- SSH access

Because of this requirement, it was not possible to create the base image entirely with Packer in the same way as with Ubuntu or other Linux distributions. Instead, a manual installation approach was used.

The base image was created following the instructions in the following repository:

[hth-nixos](https://github.com/hth73/hth-nixos)

After the installation was completed, the virtual machine was exported as a Vagrant box named nixos-base.box.

### Export the Vagrant Box

```bash
cd ../vagrant/nixos

vagrant plugin install vagrant-disksize

VBoxManage list vms
# ...
# "nixos-base" {bbbc43dd-2f59-4006-b3e9-dec8be91c1ad}

vagrant package --base nixos-base --output nixos-base.box
```

### Initialize and Start the Vagrant Box

```bash
# Add the generated Vagrant box
vagrant box add nixos-base nixos-base.box --force

# Start the NixOS virtual machine
vagrant up
```
