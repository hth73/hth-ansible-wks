# Flatcar Linux Ignition File

<img src="https://img.shields.io/badge/Flatcar%20Linux-4A90D9?style=flat&logo=linux&labelColor=ffffff&logoColor=4A90D9" /> <img src="https://img.shields.io/badge/Fedora%20Butane-51A2DA?style=flat&logo=fedora&labelColor=ffffff&logoColor=51A2DA" />

---

[Back to Flatcar Linux](../README.md)

---
### Prepare the Ignition file

```bash
# --------------------------------------------------
# Download and install Butane
# --------------------------------------------------
sudo wget -O /usr/local/bin/butane https://github.com/coreos/butane/releases/download/v0.29.0/butane-x86_64-unknown-linux-gnu
sudo chmod +x /usr/local/bin/butane

butane --version
# Butane 0.29.0

# --------------------------------------------------
# Convert Ignition file
# --------------------------------------------------
cd packer/flatcar/config
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
# flatcar.pkr.hcl
# --------------------------------------------------
variable "iso_path" {
  type    = string
  default = "file:///..../images/flatcar_production_iso_image.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:af582531593f6f425ecba1a666d97529350ef29ec09fe3acee16142d5d247710"
}
...

variable "ignition_file" {
  type    = string
  default = "ansible_config.ign"
}

source "virtualbox-iso" "flatcar" {
  ...
  # ------------------------------------------------
  # Boot and Installation
  # ------------------------------------------------
  boot_wait = "30s"

  boot_command = [
    "<enter><wait10s>",
    "wget -qO /tmp/flatcar.ign http://{{ .HTTPIP }}:{{ .HTTPPort }}/${var.ignition_file} && sudo flatcar-install -d /dev/sda -C ${var.flatcar_channel} -V ${var.flatcar_version} -i /tmp/flatcar.ign && sudo reboot",
    "<enter>"
  ]
```
