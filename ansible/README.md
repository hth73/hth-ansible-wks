# The Ansible Playbook and Roles Section

<img src="https://img.shields.io/badge/Ansible-d5000e?logo=ansible&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/sops-3e484d?logo=gnuprivacyguard&logoColor=white&style=flat" />

---

[Back to home](../README.md)

---

## Description

This section provides an overview of the playbook structure and roles, and explains how SOPS is used to securely manage secrets such as passwords.

### SOPS: Secrets OPerationS integration to securing secrets

```bash
# --------------------------------------------------------------------------------
# SOPS installation
# https://getsops.io - https://github.com/getsops
# --------------------------------------------------------------------------------
cd /tmp
wget https://github.com/getsops/sops/releases/download/v3.12.2/sops-v3.12.2.linux.amd64
mv sops-v3.12.2.linux.amd64 ~/bin/sops
chmod +x ~/bin/sops

sops --version --check-for-updates
sops 3.12.2 (latest)

# --------------------------------------------------------------------------------
# Set up sops with age and age-keygen
# https://github.com/FiloSottile/age
# --------------------------------------------------------------------------------
wget https://github.com/FiloSottile/age/releases/download/v1.3.1/age-v1.3.1-linux-amd64.tar.gz
tar xvf age-v1.3.1-linux-amd64.tar.gz
mv age/age ~/bin
mv age/age-keygen ~/bin

age -version
age-keygen -version

# ---

mkdir ~/.sops
age-keygen -o ~/.sops/sops_key.txt

cat ~/.sops/sops_key.txt

vi ~/.zshrc
export SOPS_AGE_KEY_FILE="${HOME}/.sops/sops_key.txt"
```

### Set up sops for Ansible

```bash
## Create a folder and a sops rule file
mkdir ansible/secrets

## add the age key from the file "cat ~/.sops/sops_key.txt"
vi ansible/.sops.yaml
# creation_rules:
#   - path_regex: secrets/.*\.yml$
#     encrypted_regex: ^(password|ssh_keys)$
#     age: age17kmzf3h6dz ....................9

## Install Ansible Community SOPS
ansible-galaxy collection install community.sops

## Link "community.sops.sops" in "ansible.cfg"
vi ansible/ansible.cfg
# [defaults]
# ...
# vars_plugins_enabled = host_group_vars,community.sops.sops

## Customize the ansible playbook
vi ansible/playbooks/workstation.yml

# - hosts: all
#   become: true
#   vars:
#     sops_users: "{{ lookup('community.sops.sops', '../secrets/users.sops.yml') | from_yaml }}"
#     users: "{{ sops_users.users }}"

#   roles:
#     - base
```

### Create users via Ansible

```bash
## Ansible User Module
## https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/user_module.html

## Simple Ansible Code
- name: Add the user "james" with a Bash shell and all groups.
  user:
    name: james
    password: "$6$8cYzPRMPDtKwlA1b$D6bCuTXVvxXaAv8aRA2A4V5lFuDZjOA73IhxVSdNdBj/GzKo..xitdf/jR86/BebQf4A9PJYuhtYs.tyK4I5U." # openssl passwd -6 MySecurePa$$w0rd!
    shell: /bin/bash
    groups: group1,group2
    append: yes

## Now create your own user.sops.yml file and encrypt it using sops.
cd ansible
sops secrets/users.sops.yml

## Examle Data for the secrets/users.sops.yml File
users:
  - name: < username >
    password: < Set your password using the following format: "openssl passwd -6 MySecurePa$$w0rd!" >
    groups:
      - adm
      - cdrom
      - sudo
      - dip
      - plugdev
      - users
      - lpadmin
    shell: /bin/bash
    ssh_keys:
      - ssh-ed25519 AAAAC3N....FYlT user1
      - ssh-ed25519 AAAAC4N....FYlT user2

## After the secrets/users.sops.yml file is saved, sops automatically encrypt it
cat secrets/users.sops.yml

users:
    - name: username
      password: ENC[AES256_GCM,data:q......=,type:str]
      groups:
        - adm
        - ...
      shell: /bin/bash
      ssh_keys:
        - ENC[AES256_GCM,data:q.....==,type:str]
        - ENC[AES256_GCM,data:h.....==,type:str]

sops:
    age:
        - recipient: age17kmzf3h6dz ....................9
          enc: |
            -----BEGIN AGE ENCRYPTED FILE-----
            YW....A==
            -----END AGE ENCRYPTED FILE-----
    lastmodified: "2026-04-18T15:22:41Z"
    mac: ENC[AES256_GCM,data:q......=,type:str]
    encrypted_regex: ^(password|ssh_keys)$
    version: 3.12.2
```
