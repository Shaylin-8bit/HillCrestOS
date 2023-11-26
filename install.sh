#!/usr/bin/bash

# Set OS name and place holders for possible partions
OSNAME="HillCrest OS"
ROOTSIZE=0
SWAPSIZE=0


###########################################
#
#  CONFIGURE PACMAN
#
###########################################

if [ "${1}" != "-p" ]; then

  pacman -Sy
  pacman -S reflector --noconfirm
  echo "Updating mirrors..."
  reflector --country "US" --sort rate -n 12 -l 12 --save /etc/pacman.d/mirrorlist
  pacman -S dialog --noconfirm

fi

###########################################
#
#  COLLECT USER INPUT  
#
###########################################

# Collect user information
NAME=$(dialog --stdout --title "${OSNAME}" --inputbox "Enter your username" 5 40)
HOSTNAME=$(dialog --stdout --title "${OSNAME}" --inputbox "Enter your computer's name" 5 40)
PASSWORD=$(dialog --stdout --title "${OSNAME}" --passwordbox "Enter your password" 5 40)
PASSVERI=$(dialog --stdout --title "${OSNAME}" --passwordbox "Verify your password" 5 40)

# Collect password
while [ $PASSWORD != $PASSVERI ]; do
    dialog --stdout --title "${OSNAME}" --msgbox "Passwords did not match!" 5 40
    PASSWORD=$(dialog --stdout --title "${OSNAME}" --passwordbox "Enter your password" 5 40)
    PASSVERI=$(dialog --stdout --title "${OSNAME}" --passwordbox "Verify your password" 5 40)
done

# Ask for home/root partion creation
dialog --stdout --title "${OSNAME}" --yesno "Create separate root/home partions?" 5 40
SEPARATE=$?

# Get root partion size
if [ $SEPARATE -eq 0 ]; then 
  ROOTSIZE="$(dialog --stdout --title "${OSNAME}" --inputbox "Enter root partion size in gigabytes (16 min)" 5 40)"
fi

# Ask about hibernation partion
dialog --stdout --title "${OSNAME}" --yesno "Create hibernation partion?" 5 40
SWAP=$?

# Hibernation partion should be same as RAM size
if [ $SWAP -eq 0 ]; then
  SWAPSIZE=$(free --giga | grep "Mem:" | awk '{print $2}')
fi

# Get which disk we should install on
DISKS=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop|rom" | tac)
DISK=$(dialog --stdout --title "${OSNAME}" --menu "Select installation disk" 0 0 0 ${DISKS}) || exit 1

# Create preview message
MESSAGE="Username: $NAME\nPC Name: $HOSTNAME\nDisk: $DISK\n"
if [ $SWAPSIZE -gt 0 ]; then
  MESSAGE="${MESSAGE}Swap Partion: ${SWAPSIZE}G\n"
else
  MESSAGE="${MESSAGE}No swap partion\n"
fi

if [ $ROOTSIZE -gt 0 ]; then
  MESSAGE="${MESSAGE}Root Partion: ${ROOTSIZE}G\n"
else
  MESSAGE="${MESSAGE}No separate root\home partion\n"
fi

dialog --stdout --title "${OSNAME} : System Preview" --yesno "$MESSAGE" 0 0
PROCEED=$?

# If user does not want to proceed than exit
if [ $PROCEED -eq 1 ]; then
  clear
  echo "Cancelled Installation"
  exit 1
fi

# Begin installation
clear
echo "Installing HillCrest OS"


###########################################
#
#  BEGIN PARTIONING DISK
#
###########################################

# Create temp file to hold disk partion scheme for sfdisk
touch disk.txt
truncate -s 0 disk.txt
PARTION_SCHEME="label: gpt\n\nstart= , size=550M, type=uefi, bootable\n"

# Partion scheme for swam
if [ $SWAPSIZE -gt 0 ]; then
  PARTION_SCHEME="${PARTION_SCHEME}start= , size=${SWAPSIZE}G, type=swap\n"
fi

# Partion sheme for root
if [ $ROOTSIZE -gt 0 ]; then
  PARTION_SCHEME="${PARTION_SCHEME}start= , size=${ROOTSIZE}G, type=linux\n"
fi

PARTION_SCHEME="${PARTION_SCHEME}start= , size= , type=linux"

# write to temp file
echo -e "${PARTION_SCHEME}" >> disk.txt

# write to disk
sfdisk --force $DISK < disk.txt

# delete temp file
rm disk.txt


###########################################
#
#  CREATE FILESYSTEMS
#
###########################################


# Place holders for partion paths
ROOT_PART=""
HOME_PART=""

# If swap was requested
if [ $SWAPSIZE -gt 0 ]; then
  # get swap path, wipe old file system, make swap file system, turn on swap
  # PARTION 2!!
  SWAP_PART=$(ls $DISK* | grep -E "^${DISK}?p2" | cat)
  wipefs "${SWAP_PART}"
  mkswap "${SWAP_PART}"

  # Get root path, wipe old file system, make ext4 file system
  # PARTION 3!!
  ROOT_PART=$(ls $DISK* | grep -E "^${DISK}?p3" | cat)
  wipefs "${ROOT_PART}"
  mkfs -F -t ext4 "${ROOT_PART}"
  
  # Is separate home was requested
  # PARTION 4!!
  if [ $ROOTSIZE -gt 0 ]; then
    # Get home path, wipe old file system, make ext4 file system
    HOME_PART=$(ls $DISK* | grep -E "^${DISK}?p4" | cat)
    wipefs "${HOME_PART}"
    mkfs -F -t ext4 "${HOME_PART}"
  fi

# If swap was not requested
else
  # Get root path, wipe old file system, create new file system
  # Partion 2!!
  ROOT_PART=$(ls $DISK* | grep -E "^${DISK}?p2" | cat)
  wipefs "${ROOT_PART}"
  mkfs -F -t ext4 "${ROOT_PART}"

  # If separate home partion requested
  if [ $ROOTSIZE -gt 0 ]; then
    # Get home path, wipe old file system, create new file system
    # Partion 3!!
    HOME_PART=$(ls $DISK* | grep -E "^${DISK}?p3" | cat)
    wipefs "${HOME_PART}"
    mkfs -F -t ext4 "${HOME_PART}"
  fi
fi

# get boot partion path, wipe old file system, create FAT32 file system
# PARTION 1!!
BOOT_PART=$(ls $DISK* | grep -E "^${DISK}?p1" | cat)
wipefs "${BOOT_PART}"
mkfs -F -t fat -F 32 "${BOOT_PART}"


###########################################
#
#  MOUNT PARTIONS
#
###########################################


# mount root partion
mount "${ROOT_PART}" /mnt

# mount boot partion
mkdir /mnt/boot
mount "${BOOT_PART}" /mnt/boot

# mount home partion
if [ $ROOTSIZE -gt 0 ]; then
  mkdir /mnt/home
  mount "${HOME_PART}" /mnt/home
fi

# mount swap partition
swapon "${SWAP_PART}"


###########################################
#
#  INSTALL BOOT LOADER
#
###########################################


pacstrap /mnt sudo nano linux linux-firmware base base-devel networkmanager
genfstab -U /mnt >> /mnt/etc/fstab
arch-chroot /mnt bootctl install

touch /mnt/boot/loader/loader.conf
truncate -s 0 /mnt/boot/loader/loader.conf
echo -e "default hillcrest\ntimeout 3\nconsole-mode keep\neditor 0" >> /mnt/boot/loader/loader.conf

touch /mnt/boot/loader/entries/hillcrest.conf
truncate -s 0 /mnt/boot/loader/entries/hillcrest.conf
echo -e "title HillCrest OS\nlinux /vmlinuz-linux\ninitrd /initramfs-linux.img\noptions root=PARTUUID=$(blkid ${ROOT_PART} -s PARTUUID -o value) rw" >> /mnt/boot/loader/entries/hillcrest.conf

