# Ubuntu/Manjaro Linux Unattended Installation mit Packer, Vagrant und Ansible

<img src="https://img.shields.io/badge/Ubuntu-f24e20?logo=ubuntu&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/Manjaro-00bfa5?logo=manjaro&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/virtualbox-033467?logo=virtualbox&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/Packer-00affb?logo=packer&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/Ansible-d5000e?logo=ansible&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/Vagrant-0e6aec?logo=vagrant&logoColor=white&style=flat" />

---
## Beschreibung

Dieses kleine Projekt automatisiert mir meine Ubuntu- und (zukünftig) Manjaro-Desktop-VMs in VirtualBox.<br>
Ziel ist es, schnell reproduzierbare Linux-Testmaschinen bereitzustellen, ohne manuelle Installation und Konfiguration.

Der Aufbau erfolgt in drei Schritten:
1. **Packer (Image Build)**
   - Verwendet ein Ubuntu/Manjaro ISO (lokal oder remote)
   - Führt eine unbeaufsichtigte Installation (autoinstall/cloud-init) durch
   - Erstellt daraus ein minimales, wiederverwendbares Vagrant Base Image
2. **Vagrant (VM Lifecycle)**
   - Startet eine VM basierend auf dem erzeugten Base Image
   - Kümmert sich um Netzwerk, Ressourcen und SSH-Zugriff
   - Stellt eine reproduzierbare Laufzeitumgebung bereit
3. **Ansible (Provisioning)**
   - Konfiguriert die VM nach dem Start
   - Installiert Pakete und Anwendungen
   - Wendet systemweite Konfigurationen über Rollen an (z. B. base, apps, desktop)

---

### Inhaltsverzeichnis

* [Ubuntu Packer Build und Vagrant start](packer/ubuntu/README.md)
* [Manjaro Packer Build und Vagrant start](packer/manjaro/README.md)
