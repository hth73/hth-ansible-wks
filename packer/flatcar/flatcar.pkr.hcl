# --------------------------------------------------
# Required Packer Plugins
# --------------------------------------------------
packer {
  required_plugins {
    virtualbox = {
      source  = "github.com/hashicorp/virtualbox"
      version = ">= 1.0.0"
    }

    vagrant = {
      source  = "github.com/hashicorp/vagrant"
      version = ">= 1.0.0"
    }
  }
}

# --------------------------------------------------
# Variables
# --------------------------------------------------
variable "iso_path" {
  type    = string
  default = "file:///home/hth/vbox/images/flatcar_production_iso_image.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:af582531593f6f425ecba1a666d97529350ef29ec09fe3acee16142d5d247710"
}

variable "flatcar_channel" {
  type    = string
  default = "stable"
}

variable "flatcar_version" {
  type    = string
  default = "4757.2.3"
}

variable "ignition_file" {
  type    = string
  default = "ansible_config.ign"
}

variable "ssh_private_key_file" {
  type    = string
  default = "../../secrets/ssh/id_ed25519"
}

# --------------------------------------------------
# VirtualBox ISO Source
# --------------------------------------------------
source "virtualbox-iso" "flatcar" {

  iso_url      = var.iso_path
  iso_checksum = var.iso_checksum

  vm_name       = "flatcar-base"
  guest_os_type = "Linux_64"

  disk_size = 51200
  memory    = 4096
  cpus      = 2

  # Only expose the Flatcar configuration directory.
  http_directory = "config"

  # ------------------------------------------------
  # SSH Communicator
  # ------------------------------------------------
  communicator           = "ssh"
  ssh_username           = "core"
  ssh_private_key_file   = var.ssh_private_key_file
  ssh_timeout            = "30m"
  ssh_handshake_attempts = 100
  ssh_agent_auth         = false
  ssh_pty                = true

  # ------------------------------------------------
  # Boot and Installation
  # ------------------------------------------------
  boot_wait = "30s"

  boot_command = [
    "<enter><wait10s>",
    "wget -qO /tmp/flatcar.ign http://{{ .HTTPIP }}:{{ .HTTPPort }}/${var.ignition_file} && sudo flatcar-install -d /dev/sda -C ${var.flatcar_channel} -V ${var.flatcar_version} -i /tmp/flatcar.ign && sudo reboot",
    "<enter>"
  ]

  # ------------------------------------------------
  # Shutdown
  # ------------------------------------------------
  shutdown_command = "sudo systemctl poweroff"
}

# --------------------------------------------------
# Build
# --------------------------------------------------
build {
  sources = [
    "source.virtualbox-iso.flatcar"
  ]

  post-processor "vagrant" {
    output              = "flatcar-base.box"
    keep_input_artifact = false
  }
}
