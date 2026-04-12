#!/usr/bin/env bash
set -euxo pipefail

# debug logging
exec > /root/install.log 2>&1

echo "===> START INSTALL"

# disk automatisch erkennen
DISK=$(lsblk -ndo NAME,TYPE | awk '$2=="disk"{print "/dev/"$1; exit}')
PART="${DISK}1"

echo "Using disk: $DISK"

# partitionierung
parted -s "$DISK" mklabel msdos
parted -s "$DISK" mkpart primary ext4 1MiB 100%
parted -s "$DISK" set 1 boot on

# warten damit Kernel die Partition sieht
sleep 5

# filesystem
mkfs.ext4 -F "$PART"
mount "$PART" /mnt

# time fix
timedatectl set-ntp true
sleep 5

# keyring fix (untrusted packages)
cat > /etc/pacman.d/mirrorlist <<'EOF'
Server = https://ftp.gwdg.de/pub/linux/manjaro/stable/$repo/$arch
Server = https://mirror.netcologne.de/manjaro/stable/$repo/$arch
EOF

pacman -Syy

sed -i 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf

pacman-key --init || true
pacman-key --populate archlinux manjaro || true

# update keys
pacman -Sy --noconfirm archlinux-keyring manjaro-keyring

# base installation
command -v basestrap || { echo "basestrap not found"; exit 1; }
basestrap /mnt base base-devel linux linux-firmware mkinitcpio systemd sudo openssh grub networkmanager

# fstab
UUID=$(blkid -s UUID -o value ${PART})

cat > /mnt/etc/fstab <<EOF
UUID=$UUID / ext4 defaults 0 1
EOF

# system konfigurieren
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys

chroot /mnt /bin/bash <<'EOF'

set -euxo pipefail

echo "===> START CHROOT CONFIG"

echo "===> UPDATE KEYRING"
pacman-key --init
pacman-key --populate archlinux manjaro
pacman -Sy manjaro-keyring --noconfirm --disable-sandbox

echo "===> INSTALL PACKAGES"
pacman -S vim nano git curl --noconfirm --disable-sandbox

echo "===> SET HOSTNAME"
# Hostname
echo "manjaro-client" > /etc/hostname

echo "===> SET LOCALE"
# Locale
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=de" > /etc/vconsole.conf

echo "===> CHANGE ROOT PWD"
# Root Passwort
echo "root:root" | chpasswd

echo "===> CREATE VAGRANT USER"
useradd -m -s /bin/bash vagrant
echo "vagrant:vagrant" | chpasswd
echo "vagrant ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vagrant
chmod 440 /etc/sudoers.d/vagrant

echo "===> INSTALL SSH KEY"
mkdir -p /home/vagrant/.ssh
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJVpcUidKX5g1Ydq4HW3H560hVzVD5pEHbM8zHHwFYlT spox@vagrant-dev" > /home/vagrant/.ssh/authorized_keys
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

EOF

# Cleanup
umount -R /mnt

echo "===> INSTALL DONE"

# sauber herunterfahren
read -p "Press ENTER to shutdown..."
bash

poweroff
