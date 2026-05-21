# CoreOS Ignition File

<img src="https://img.shields.io/badge/Fedora%20CoreOS-51A2DA?style=flat&logo=fedora&labelColor=ffffff&logoColor=51A2DA" /> <img src="https://img.shields.io/badge/Fedora%20Butane-51A2DA?style=flat&logo=fedora&labelColor=ffffff&logoColor=51A2DA" />

---

[Back to Fedora CoreOS](../README.md)

---
### Prepare the Ignition file

```bash
# --------------------------------------------------
# Download and install Butane
# --------------------------------------------------
sudo wget -O /usr/local/bin/butane https://github.com/coreos/butane/releases/download/v0.27.0/butane-x86_64-unknown-linux-gnu
sudo chmod +x /usr/local/bin/butane

butane --version
# Butane 0.27.0

# --------------------------------------------------
# Convert Ignition file
# --------------------------------------------------
cd packer/coreos/config
butane --pretty --strict ansible_config.bu > ansible_config.ign

# --------------------------------------------------
# Create an ignition hash and use it in Packer
# --------------------------------------------------
sha256sum ansible_config.ign
# 3834f44c52b0b80e..........
# or
sha512sum ansible_config.ign
# 9c4f683ab01ca78f..........
```
```yaml
# --------------------------------------------------
# fedora-coreos.pkr.hcl
# --------------------------------------------------
...

variable "ignition_file" {
  type    = string
  default = "config/ansible_config.ign"
}

variable "ignition_hash" {
  type    = string
  default = "sha256-3834f44c52b0b80e.........."
  # default = "sha512-9c4f683ab01ca78f.........."
}

source "virtualbox-iso" "coreos" {
  ...
  http_directory = "."

  boot_command = [
    ...
    "sudo coreos-installer install /dev/sda --ignition-hash '${var.ignition_hash}' --ignition-url 'http://{{ .HTTPIP }}:{{ .HTTPPort }}/${var.ignition_file}'",
    ...
}
```
