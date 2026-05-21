## required packer plugins for the installation
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

variable "iso_path" {
  type    = string
  default = "file:///home/hth/vbox/images/fedora-coreos-44.20260419.3.1-live-iso.x86_64.iso"
}

variable "ignition_file" {
  type    = string
  default = "config/ansible_config.ign"
}

variable "ignition_hash" {
  type    = string
  default = "sha256-3834f44c52b0b80ea9b3af9b47dd7a4afe4d65c32165a053fca1310e3179383c"
}

variable "ssh_private_key_file" {
  type    = string
  default = "../../secrets/ssh/id_ed25519"
}

source "virtualbox-iso" "coreos" {
  iso_url      = var.iso_path
  iso_checksum = "none"

  vm_name       = "coreos-base"
  guest_os_type = "Fedora_64"

  disk_size = 20480
  memory    = 4096
  cpus      = 2

  http_directory = "."

  communicator           = "ssh"
  ssh_username           = "core"
  ssh_private_key_file   = var.ssh_private_key_file
  ssh_timeout            = "30m"
  ssh_handshake_attempts = 100
  ssh_agent_auth         = false
  ssh_pty                = true

  boot_wait = "5s"

  # Wait for:
  # - coreos-installer to finish
  # - first boot with Ignition
  # - rpm-ostree package layering
  # - automatic reboot after package installation
  boot_command = [
    "<enter>",
    "<wait30s>",
    "sudo coreos-installer install /dev/sda --ignition-hash '${var.ignition_hash}' --ignition-url 'http://{{ .HTTPIP }}:{{ .HTTPPort }}/${var.ignition_file}'",
    "<enter>",
    "<wait5m>",
    "sudo reboot",
    "<enter>"
  ]
  shutdown_command = "sudo systemctl poweroff"
}

build {
  sources = ["source.virtualbox-iso.coreos"]

  post-processor "vagrant" {
    output              = "coreos-base.box"
    keep_input_artifact = false
  }
}
