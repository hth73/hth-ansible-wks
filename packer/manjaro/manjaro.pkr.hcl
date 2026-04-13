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

source "virtualbox-iso" "manjaro" {
  iso_url      = "/home/hth/vbox/images/manjaro-gnome-26.0.4-260327-linux618-custom.iso"
  iso_checksum = "none"

  vm_name = "manjaro-client"
  guest_os_type = "ArchLinux_64"

  cpus                 = 2
  memory               = 4096
  disk_size            = 20000
  hard_drive_interface = "sata"

  boot_wait = "10s"

  communicator            = "none"
  virtualbox_version_file = ""
  guest_additions_mode    = "disable"
  shutdown_timeout        = "60m"
  
  shutdown_command        = "shutdown -P now"

  vboxmanage = [
    ["modifyvm", "{{.Name}}", "--boot1", "dvd"],
    ["modifyvm", "{{.Name}}", "--boot2", "disk"],
    ["modifyvm", "{{.Name}}", "--boot3", "none"],
    ["modifyvm", "{{.Name}}", "--boot4", "none"],

    ["modifyvm", "{{.Name}}", "--graphicscontroller", "vmsvga"],
    ["modifyvm", "{{.Name}}", "--vram", "128"],
    ["modifyvm", "{{.Name}}", "--firmware", "bios"]
  ]
}

build {
  sources = ["source.virtualbox-iso.manjaro"]

  post-processor "vagrant" {
    output = "manjaro-client.box"
    keep_input_artifact = false
  }
}
