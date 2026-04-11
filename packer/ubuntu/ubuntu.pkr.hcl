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
  default = "file:///home/hth/vbox/images/ubuntu-24.04.4-desktop-amd64.iso"
}

source "virtualbox-iso" "ubuntu" {
  iso_url                = var.iso_path
  iso_checksum           = "sha256:3a4c9877b483ab46d7c3fbe165a0db275e1ae3cfe56a5657e5a47c2f99a99d1e" # sha256sum ../ubuntu-24.04.4-desktop-amd64.iso

  vm_name                = "ubuntu-client"
  guest_os_type          = "Ubuntu_64"

  communicator           = "ssh"
  ssh_host               = "127.0.0.1"
  ssh_username           = "vagrant"
  ssh_password           = "vagrant"
  ssh_timeout            = "20m"
  ssh_handshake_attempts = 50
  ssh_agent_auth         = false
  ssh_pty                = true

  http_directory         = "http"

  boot_wait    = "10s"
  boot_command = [
    "<wait>",
    "e<wait>",
    "<down><down><down><end><wait>",
    " autoinstall cloud-config-url=/dev/null ds=nocloud\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/",
    "<f10>"
  ]

  shutdown_command = "echo 'packer' | sudo -S shutdown -P now"

  disk_size = 20480
  memory    = 4096
  cpus      = 2

  headless = false
  # skip_export     = true
  # keep_registered = true
}

build {
  sources = ["source.virtualbox-iso.ubuntu"]
  
  post-processor "vagrant" {
    output = "ubuntu-client.box"
    keep_input_artifact = false
  }
}
