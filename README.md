# Ubuntu/Manjaro Linux Unattended Installation with Packer, Vagrant and Ansible

<img src="https://img.shields.io/badge/Ubuntu-f24e20?logo=ubuntu&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/Manjaro-00bfa5?logo=manjaro&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/virtualbox-033467?logo=virtualbox&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/Packer-00affb?logo=packer&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/Ansible-d5000e?logo=ansible&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/Vagrant-0e6aec?logo=vagrant&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/sops-3e484d?logo=gnuprivacyguard&logoColor=white&style=flat" />

---

## Description

This project automates the creation of my Ubuntu and Manjaro desktop VMs in VirtualBox.<br>
The goal is to quickly provide reproducible Linux test environments without manual installation and configuration.

The setup is divided into three stages:
1. **Packer (Image Build)**
   - Uses an Ubuntu/Manjaro ISO (local or remote)
   - Performs an unattended installation (autoinstall/cloud-init)
   - Builds a minimal, reusable Vagrant base image
2. **Vagrant (VM Lifecycle)**
   - Starts a VM based on the generated base image
   - Manages networking, resources, and SSH access
   - Provides a reproducible runtime environment
3. **Ansible (Provisioning)**
   - Configures the VM after startup
   - Installs packages and applications
   - Applies system-wide configuration using roles (e.g. base, apps, desktop)

---

### Table of Contents

* [Ubuntu Packer Build and Vagrant Startup](packer/ubuntu/README.md)
* [Manjaro Packer Build and Vagrant Startup](packer/manjaro/README.md)
* [The Ansible Playbook and Roles Section](ansible/README.md)
