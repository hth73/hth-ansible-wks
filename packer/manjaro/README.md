# Manjaro Packer Build und Vagrant start

<img src="https://img.shields.io/badge/Manjaro-00bfa5?logo=manjaro&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/virtualbox-033467?logo=virtualbox&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/Packer-00affb?logo=packer&logoColor=white&style=flat" /> <img src="https://img.shields.io/badge/Vagrant-0e6aec?logo=vagrant&logoColor=white&style=flat" />

---

[Back to home](../../README.md)

---
### Manjaro Packer Build vorbereiten

Das Manjaro Live Image wurde mit einem eigenen **install.sh** Skript ausgestattet, um eine vollständig automatisierte Basisinstallation zu ermöglichen. Ziel war es, den manuellen Installationsprozess so zu verändern, damit sich dieser in dem Packer-Build integrieren lässt.

Technisch läuft die Installation wie folgt ab. Packer startet das angepasste ISO Image und bootet die VM, das **install.sh** Skript wird dann automatisch im Hintergrund über eine eigenen Systemd Datei gestartet und in der Live Umgebung ausgeführt. Das Skript installiert im gemounteten Root Filesystem seine Pakete und konfiguriert mittels chroot die neue Umgebung. Nach Abschluss der Installation wird die Maschine kontrolliert heruntergefahren, sodass Packer das fertige Image weiterverarbeiten und als Vagrant Box exportieren kann.

### ISO Image für den Import der install.sh vorbereiten
Nachdem man sich das Manjaro ISO Image heruntergeladen hat, muss man das ISO Image extrahieren um an das rootfs Filesystem ranzukommen. In dieses rootfs Filesystem kopieren wir dann unsere spätere **install.sh** Skript.

```bash
## Ordnerstruktur anlegen
cd ~/vbox
mkdir -p manjaro-iso rootfs

## ISO Image extrahieren
sudo apt install libarchive-tools xorriso -y

## manjaro-gnome-26.0.4-260327-linux618.iso extrahieren
##
bsdtar -C manjaro-iso -xf manjaro-gnome-26.0.4-260327-linux618.iso

ls -la manjaro-iso
# .r--r--r--    0 hth 28 Mar 00:23 .miso
# ...
# .r--r--r-- 4.2M hth 28 Mar 00:23 efi.img
# dr-xr-xr-x    - hth 28 Mar 00:23 manjaro

## RootFS Filesystem extrahieren - manjaro-iso/manjaro/x86_64/rootfs.sfs
##
unsquashfs -d rootfs manjaro-iso/manjaro/x86_64/rootfs.sfs
# Parallel unsquashfs: Using 12 processors
# 79591 inodes (68201 blocks) to write
# ...
# Further error messages of this type are suppressed!
# [=====================================================\] 147792/147792 100%
# created 63017 files
# created 6468 directories
# created 11509 symlinks
# ...
# created 5065 hardlinks
```

### Meine install.sh - Experiment - ohne Gewähr!!
Hier gabe es sehr viele Probleme im Live System, angefangen von der Zeitsynchronisation über unsignierte Paket Quellen, bis hin zu falschen Toolnamen. Die bei ArchLinux beschrieben wurden, aber in Manjaro anders heißen.
Der Link war mein Ausgangspunkt und sehr viele Stunden debugging.
https://wiki.archlinux.org/title/Installation_guide

Mein Debugging erfolgte in der VM über ein virtuelles Terminal (tty3) (STRG+ALT+F3). Anmeldung am Live System ist möglich, als Benutzer **manjaro/manjaro** oder als **root/manjaro**.

```bash
## Logging ansehen nach der Anmeldung im Live System
## über ein virtuelles Terminal (tty3)
tail -f /root/install.sh
cat /root/install.sh | less

## Wenn Packer die Vagrant Box erstellt hat, 
## findet man auch die Log Datei im fertigen Image.
sudo cat /root/install.log | less
```

```bash
#!/usr/bin/env bash
set -euxo pipefail

# debug logging
exec 3>&1 4>&2
exec > >(tee -a /root/install.log) 2>&1

echo "===> START INSTALL"

# detect the disk
DISK=$(lsblk -ndo NAME,TYPE | awk '$2=="disk"{print "/dev/"$1; exit}')
PART="${DISK}1"

echo "Using disk: $DISK"

# partitioning
parted -s "$DISK" mklabel msdos
parted -s "$DISK" mkpart primary ext4 1MiB 100%
parted -s "$DISK" set 1 boot on

# wait until the kernel detects the partition
sleep 5

# filesystem
mkfs.ext4 -F "$PART"
mount "$PART" /mnt

mkdir -p /mnt/root
exec > >(tee -a /root/install.log /mnt/root/install.log) 2>&1

# fix time issue
timedatectl set-ntp true
sleep 10

# keyring fix (untrusted packages)
sed -i 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf

cat > /etc/pacman.d/mirrorlist <<'EOF'
Server = https://ftp.gwdg.de/pub/linux/manjaro/stable/$repo/$arch
Server = https://mirror.netcologne.de/manjaro/stable/$repo/$arch
EOF

pacman-key --init || true
pacman -Syy
pacman -Sy --needed --noconfirm pacman glibc manjaro-system archlinux-keyring manjaro-keyring
sleep 10

# base installation
command -v basestrap || { echo "basestrap not found"; exit 1; }
basestrap /mnt base base-devel linux linux-firmware mkinitcpio systemd sudo vim openssh grub networkmanager mhwd mhwd-db

# fstab
UUID=$(blkid -s UUID -o value "${PART}")

cat > /mnt/etc/fstab <<EOF
UUID=$UUID / ext4 defaults 0 1
EOF

# system configuration
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys

chroot /mnt /bin/bash -c '
set -euxo pipefail

echo "===> START CHROOT CONFIG"

echo "===> SET HOSTNAME"
echo "manjaro-client" > /etc/hostname

echo "===> SET LOCALE"
sed -i "s/^#en_US.UTF-8/en_US.UTF-8/" /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=de" > /etc/vconsole.conf

echo "===> CHANGE ROOT PWD"
echo "root:root" | chpasswd

echo "===> CREATE VAGRANT USER"
useradd -m -s /bin/bash vagrant
echo "vagrant:vagrant" | chpasswd
echo "vagrant ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vagrant
chmod 440 /etc/sudoers.d/vagrant

echo "===> INSTALL SSH KEY"
mkdir -p /home/vagrant/.ssh
echo "ssh-ed25519 AA...lT spox@vagrant-dev" > /home/vagrant/.ssh/authorized_keys
chmod 700 /home/vagrant/.ssh
chmod 600 /home/vagrant/.ssh/authorized_keys
chown -R vagrant:vagrant /home/vagrant/.ssh

echo "===> ENABLE SERVICE"
systemctl enable sshd
systemctl enable NetworkManager

echo "===> BOOTLOADER CONFIG"
grub-install --target=i386-pc /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

echo "===> INITRAMFS CONFIG"
mkinitcpio -P

echo "===> CHROOT CONFIG DONE"
'

# stop logging and cleanup
exec 1>&3 2>&4
umount -R /mnt

echo "===> INSTALL DONE"

# shutdown system
poweroff
```

### Skript in das RootFS kopieren und ISO Image erstellen

```bash
## install.sh kopieren und berechtigen
cp install.sh rootfs/usr/local/bin/install.sh
chmod +x rootfs/usr/local/bin/install.sh

ls -la rootfs/usr/local/bin/install.sh
# .rwxrwxr-x 1.5k hth 12 Apr 15:26 rootfs/usr/local/bin/install.sh

## Systemd Datei erstellen damit diese nach dem booten ausgeführt wird
vi rootfs/etc/systemd/system/install.service

# ---
[Unit]
Description=Auto Install Manjaro
After=network-online.target
Wants=network-online.target

ConditionPathExists=!/root/install.done

[Service]
Type=oneshot
User=root
ExecStart=/usr/bin/bash /usr/local/bin/install.sh
ExecStartPost=/usr/bin/touch /root/install.done

StandardOutput=journal
StandardError=journal

RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
# ---

## Systemd Datei in multi-user.target.wants verlinken
ln -s /etc/systemd/system/install.service rootfs/etc/systemd/system/multi-user.target.wants/install.service

ls -la rootfs/etc/systemd/system/multi-user.target.wants                                                   
# lrwxrwxrwx - hth 12 Apr 15:32 install.service -> /etc/systemd/system/install.service
# ...

## neue rootfs.sfs Datei schreiben
sudo mksquashfs rootfs manjaro-iso/manjaro/x86_64/rootfs.sfs -comp xz -noappend

# Parallel mksquashfs: Using 12 processors
# Creating 4.0 filesystem on manjaro-iso/manjaro/x86_64/rootfs.sfs, block size 131072.
# [====================================================================================|] 74814/74814 100%
# Exportable Squashfs 4.0 filesystem, xz compressed, data block size 131072
#   compressed data, compressed metadata, compressed fragments,
#   compressed xattrs, compressed ids
#   duplicates are removed
# Filesystem size 962030.28 Kbytes (939.48 Mbytes)
#   44.34% of uncompressed filesystem size (2169897.73 Kbytes)
# Inode table size 597740 bytes (583.73 Kbytes)
#   20.63% of uncompressed inode table size (2898111 bytes)
# Directory table size 739934 bytes (722.59 Kbytes)
#   33.12% of uncompressed directory table size (2234165 bytes)
# ...

## Nachdem die rootfs.sfs geschrieben wurde, passt der dazugehörige MD5 Hash "rootfs.md5" nicht mehr.
## Dieser muss ebenfalls angepasst werden.
ls -la manjaro-iso/manjaro/x86_64
# ...
# .r--r--r--   45 hth 28 Mar 00:39 rootfs.md5
# .r--r--r-- 985M hth 12 Apr 15:34 rootfs.sfs

## rootfs.md5 Datei editierbar machen
## Den MD5 Hash neu erstellt und in die rootfs.md5 schreiben.
sudo chmod 0644 manjaro-iso/manjaro/x86_64/rootfs.md5

cat manjaro-iso/manjaro/x86_64/rootfs.md5
# 9eef1847ab8135d876eb50f71278d59b  rootfs.sfs

md5sum manjaro-iso/manjaro/x86_64/rootfs.sfs
# 976f6de30653fb593ce6de8a0a6159fb  manjaro-iso/manjaro/x86_64/rootfs.sfs

sudo vi manjaro-iso/manjaro/x86_64/rootfs.md5
cat manjaro-iso/manjaro/x86_64/rootfs.md5
# 976f6de30653fb593ce6de8a0a6159fb  rootfs.sfs

sudo chmod 0444 manjaro-iso/manjaro/x86_64/rootfs.md5

ls -la manjaro-iso/manjaro/x86_64        
# ...
# .r--r--r--   45 hth 12 Apr 15:40 rootfs.md5
# .r--r--r-- 985M hth 12 Apr 15:34 rootfs.sfs

## Mein Custom Manjaro Linux ISO Image für spätere Vagrant Box
xorriso -as mkisofs \
  -iso-level 3 \
  -o manjaro-gnome-26.0.4-260327-linux618-custom.iso \
  -full-iso9660-filenames \
  -volid "MANJARO_CUSTOM" \
  -eltorito-boot boot/grub/i386-pc/eltorito.img \
  -no-emul-boot \
  -boot-load-size 4 \
  -boot-info-table \
  -eltorito-alt-boot \
  -e efi.img \
  -no-emul-boot \
  manjaro-iso

# xorriso 1.5.6 : RockRidge filesystem manipulator, libburnia project.
# Drive current: -outdev 'stdio:manjaro-custom.iso'
# Media current: stdio file, overwriteable
# Media status : is blank
# Media summary: 0 sessions, 0 data blocks, 0 data,  701g free
# Added to ISO image: directory '/'='/home/hth/vbox/manjaro-iso'
# xorriso : UPDATE :     867 files added in 1 seconds
# xorriso : UPDATE :     867 files added in 1 seconds
# xorriso : UPDATE :  0.12% done
# ...
# xorriso : UPDATE :  88.75% done
# ISO image produced: 2678593 sectors
# Written to medium : 2678593 sectors at LBA 0
# Writing to 'stdio:manjaro-custom.iso' completed successfully.
```

### Packer build initialisieren und starten

```bash
cd packer/manjaro
packer init manjaro.pkr.hcl
packer build manjaro.pkr.hcl
```

### Vagrant Box initialisieren und starten

```bash
## Manjaro VM starten
cd ../vagrant/manjaro
vagrant box add ../../packer/manjaro/manjaro-client.box --name manjaro-client --force
vagrant up
```
