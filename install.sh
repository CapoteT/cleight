echo "     Easy-to-configure archlinux+bspwm install script ";
echo "        for maximum comfort and minimum hassles ";
echo "";
echo "";


# checks wheter there is multilib repo enabled properly or not
IS_MULTILIB_REPO_DISABLED=$(cat /etc/pacman.conf | grep "#\[multilib\]" | wc -l)
if [ "$IS_MULTILIB_REPO_DISABLED" == "1" ]
then
    echo "You need to enable [multilib] repository inside /etc/pacman.conf file before running this script, aborting installation"
    exit -1
fi
echo "[multilib] repo correctly enabled, continuing"

# syncing system datetime
timedatectl set-ntp true

# updating mirrors
pacman -Syyy

# adding fzf for making disk selection easier
pacman -S fzf --noconfirm

# open dialog for disk selection
selected_disk=$(sudo fdisk -l | grep 'Disk /dev/' | awk '{print $2,$3,$4}' | sed 's/,$//' | fzf | sed -e 's/\/dev\/\(.*\):/\1/' | awk '{print $1}')

# formatting disk for UEFI install
echo "Formatting disk for UEFI install"
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk /dev/${selected_disk}
  g # gpt partitioning
  n # new partition
    # default: primary partition
    # default: partition 1
  +500M # mb on boot partition
    # default: yes if asked
  n # new partition
    # default: primary partition
    # default: partition 2
    # default: all space left for lvm partition
    # default: yes if asked
  t # change partition type
  1 # selecting partition 1
  1 # selecting EFI partition type
  t # change partition type
  2 # selecting partition 2
  30 # selecting LVM partition type
  w # writing changes to disk
EOF

# outputting partition changes
fdisk -l /dev/${selected_disk}

# partition bootloader EFI partition
yes | mkfs.fat -F32 /dev/${selected_disk}1

# creating lvm volumes and groups
pvcreate --dataalignment 1m /dev/${selected_disk}2
vgcreate volgroup0 /dev/${selected_disk}2
lvcreate -L 80GB volgroup0 -n lv_root
lvcreate -l 100%FREE volgroup0 -n lv_home
modprobe dm_mod
vgscan
vgchange -ay

# partition filesystem formatting
yes | mkfs.ext4 /dev/volgroup0/lv_root
yes | mkfs.ext4 /dev/volgroup0/lv_home

# disk mount
mount /dev/volgroup0/lv_root /mnt
mkdir /mnt/boot
mkdir /mnt/home
mount /dev/${selected_disk}1 /mnt/boot
mount /dev/volgroup0/lv_home /mnt/home

# pacstrap-ping desired disk
pacstrap /mnt base base-devel neovim networkmanager rofi feh linux linux-headers linux-firmware \
os-prober efibootmgr ntfs-3g kitty git zsh amd-ucode intel-ucode cpupower xf86-video-amdgpu xf86-video-nouveau \
xorg-server xorg-xinit ttf-dejavu ttf-liberation ttf-inconsolata noto-fonts gucharmap \
firefox geckodriver zip unzip unrar obs-studio adapta-gtk-theme \
pulseaudio pamixer telegram-desktop python python-pip wget nginx \
openssh xorg-xrandr noto-fonts-emoji maim imagemagick xclip \
ttf-roboto playerctl papirus-icon-theme hwloc p7zip hsetroot pdfarranger inkscape \
nemo tree man inter-font fzf mesa vulkan-radeon libva-mesa-driver mumble lvm2 \
mesa-vdpau zsh-syntax-highlighting xdotool cronie dunst entr python-dbus bind-tools gnome-keyring \
i3lock dbeaver ccache ttf-cascadia-code ttf-opensans httpie pavucontrol docker docker-compose \
mpv iotop bspwm sxhkd gitg filelight networkmanager-openvpn libreoffice sassc sshfs ufw lxde rclone pinta remmina freerdp

# generating fstab
genfstab -U /mnt >> /mnt/etc/fstab

# enabled [multilib] repo on installed system
arch-chroot /mnt zsh -c 'echo "[multilib]" >> /etc/pacman.conf'
arch-chroot /mnt zsh -c 'echo "Include = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf'

# updating repo status
arch-chroot /mnt pacman -Syyy

# setting right timezone
arch-chroot /mnt ln -sf /usr/share/zoneinfo/Europe/Warsaw /etc/localtime

# enabling font presets for better font rendering
arch-chroot /mnt ln -s /etc/fonts/conf.avail/70-no-bitmaps.conf /etc/fonts/conf.d
arch-chroot /mnt ln -s /etc/fonts/conf.avail/10-sub-pixel-rgb.conf /etc/fonts/conf.d
arch-chroot /mnt ln -s /etc/fonts/conf.avail/11-lcdfilter-default.conf /etc/fonts/conf.d
arch-chroot /mnt zsh -c `echo 'export FREETYPE_PROPERTIES="truetype:interpreter-version=38"' >> /etc/profile.d/freetype2.sh`

# synchronizing timer
arch-chroot /mnt hwclock --systohc

# localizing system
arch-chroot /mnt sed -i -e 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen
arch-chroot /mnt sed -i -e 's/#en_US ISO-8859-1/en_US ISO-8859-1/g' /etc/locale.gen

# generating locale
arch-chroot /mnt locale-gen

# setting system language
arch-chroot /mnt echo "LANG=en_US.UTF-8" >> /mnt/etc/locale.conf

# setting machine name
arch-chroot /mnt echo "cleight" >> /mnt/etc/hostname

# setting hosts file
arch-chroot /mnt echo "127.0.0.1 localhost" >> /mnt/etc/hosts
arch-chroot /mnt echo "::1 localhost" >> /mnt/etc/hosts
arch-chroot /mnt echo "127.0.1.1 cleight.localdomain cleight" >> /mnt/etc/hosts

# making sudoers do sudo stuff without requiring password typing
arch-chroot /mnt sed -i -e 's/# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/g' /etc/sudoers

# add support for root lvm2 boot and make initframs for proper boot
arch-chroot /mnt sed -i -e 's/base udev/base systemd udev/g' /etc/mkinitcpio.conf
arch-chroot /mnt sed -i -e 's/block filesystems/block lvm2 filesystems/g' /etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -p linux

# setting root password
arch-chroot /mnt sudo -u root /bin/zsh -c 'echo "Insert root password: " && read root_password && echo -e "$root_password\n$root_password" | passwd root'

# making user capote
arch-chroot /mnt useradd -m -G wheel -s /bin/zsh capote

# setting capote password
arch-chroot /mnt sudo -u root /bin/zsh -c 'echo "Insert capote password: " && read capote_password && echo -e "$capote_password\n$capote_password" | passwd capote'

# installing systemd-boot
arch-chroot /mnt bootctl --path=/boot install

# configuring cleight boot entry
arch-chroot /mnt /bin/zsh -c "grep \"UUID=\" /etc/fstab | grep '/ ' | awk '{ print \$1 }' | sed -e 's/UUID=//' > .root_disk_uuid"
arch-chroot /mnt /bin/zsh -c 'touch /boot/loader/entries/cleight.conf'
arch-chroot /mnt /bin/zsh -c 'echo "title cleight" >> /boot/loader/entries/cleight.conf'
arch-chroot /mnt /bin/zsh -c 'echo "linux /vmlinuz-linux" >> /boot/loader/entries/cleight.conf'
arch-chroot /mnt /bin/zsh -c 'echo "initrd /amd-ucode.img" >> /boot/loader/entries/cleight.conf'
arch-chroot /mnt /bin/zsh -c 'echo "initrd /intel-ucode.img" >> /boot/loader/entries/cleight.conf'
arch-chroot /mnt /bin/zsh -c 'echo "initrd /initramfs-linux.img quiet loglevel=3 vga=current" >> /boot/loader/entries/cleight.conf'
arch-chroot /mnt /bin/zsh -c 'echo options root=\"UUID=root_disk_uuid\" rw >> /boot/loader/entries/cleight.conf'
arch-chroot /mnt /bin/zsh -c 'sed -i -e "s/root_disk_uuid/$(cat .root_disk_uuid)/g" /boot/loader/entries/cleight.conf'
arch-chroot /mnt /bin/zsh -c 'rm .root_disk_uuid'

# changing governor to performance
arch-chroot /mnt echo "governor='performance'" >> /mnt/etc/default/cpupower

# making services start at boot
arch-chroot /mnt systemctl enable cpupower.service
arch-chroot /mnt systemctl enable NetworkManager.service
arch-chroot /mnt systemctl enable cronie.service
arch-chroot /mnt systemctl enable sshd.service
arch-chroot /mnt systemctl enable fstrim.timer
arch-chroot /mnt systemctl enable docker.service
arch-chroot /mnt systemctl enable ufw.service

# enabling and starting DNS resolver via systemd-resolved
arch-chroot /mnt systemctl enable systemd-resolved.service
arch-chroot /mnt systemctl start systemd-resolved.service

# making bspwm default for startx for both root and capote
arch-chroot /mnt echo "exec bspwm" >> /mnt/root/.xinitrc
arch-chroot /mnt echo "exec bspwm" >> /mnt/home/capote/.xinitrc

# installing yay
arch-chroot /mnt sudo -u capote git clone https://aur.archlinux.org/yay.git /home/capote/yay_tmp_install
arch-chroot /mnt sudo -u capote /bin/zsh -c "cd /home/capote/yay_tmp_install && yes | makepkg -si"
arch-chroot /mnt rm -rf /home/capote/yay_tmp_install

# adding makepkg optimizations
arch-chroot /mnt sed -i -e 's/#MAKEFLAGS="-j2"/MAKEFLAGS=-j'$(nproc --ignore 1)'/' -e 's/-march=x86-64 -mtune=generic/-march=native/' -e 's/xz -c -z/xz -c -z -T '$(nproc --ignore 1)'/' /etc/makepkg.conf
arch-chroot /mnt sed -i -e 's/!ccache/ccache/g' /etc/makepkg.conf

# installing various packages from AUR
arch-chroot /mnt sudo -u capote yay -S polybar --noconfirm
arch-chroot /mnt sudo -u capote yay -S spotifyd spotify --noconfirm
arch-chroot /mnt sudo -u capote yay -S corrupter-bin --noconfirm
arch-chroot /mnt sudo -u capote yay -S visual-studio-code-bin --noconfirm
arch-chroot /mnt sudo -u capote yay -S archtorify-git --noconfirm
arch-chroot /mnt sudo -u capote yay -S greetd greetd-tuigreet --noconfirm
arch-chroot /mnt sudo -u capote yay -S apple-fonts --noconfirm
arch-chroot /mnt sudo -u capote yay -S picom-ibhagwan-git --noconfirm

# adding tuigreet to boot
arch-chroot /mnt systemctl enable greetd.service

# installing oh-my-zsh
arch-chroot /mnt sudo -u capote /bin/zsh -c 'cd ~ && curl -O https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh && chmod +x install.sh && RUNZSH=no ./install.sh && rm ./install.sh'

# installing vundle
arch-chroot /mnt sudo -u capote mkdir -p /home/capote/.config/nvim/bundle
arch-chroot /mnt sudo -u capote git clone https://github.com/VundleVim/Vundle.vim.git /home/capote/.config/nvim/bundle/Vundle.vim

# installing fonts
arch-chroot /mnt sudo -u capote mkdir /home/capote/fonts_tmp_folder
arch-chroot /mnt sudo -u capote sudo mkdir /usr/share/fonts/OTF/
# material icons
arch-chroot /mnt sudo -u capote /bin/zsh -c "cd /home/capote/fonts_tmp_folder && curl -o materialicons.zip https://github.com/google/material-design-icons/releases/download/3.0.1/material-design-icons-3.0.1.zip && unzip materialicons.zip"
arch-chroot /mnt sudo -u capote /bin/zsh -c "sudo cp /home/capote/fonts_tmp_folder/material-design-icons-3.0.1/iconfont/MaterialIcons-Regular.ttf /usr/share/fonts/TTF/"
# removing fonts tmp folder
arch-chroot /mnt sudo -u capote rm -rf /home/capote/fonts_tmp_folder

# installing config files
arch-chroot /mnt sudo -u capote mkdir /home/capote/GitHub
arch-chroot /mnt sudo -u capote git clone https://github.com/CapoteT/cleight /home/capote/GitHub/cleight
arch-chroot /mnt sudo -u capote /bin/zsh -c "chmod 700 /home/capote/GitHub/cleight/install_configs.sh"
arch-chroot /mnt sudo -u capote /bin/zsh -c "cd /home/capote/GitHub/cleight && ./install_configs.sh"
arch-chroot /mnt cp /home/capote/GitHub/cleight/greetd.config.toml /etc/greetd/config.toml

# create folder for screenshots
arch-chroot /mnt sudo -u capote mkdir /home/capote/Screenshots

# create pictures folder, secrets folder and moving default wallpaper
arch-chroot /mnt sudo -u capote mkdir /home/capote/Pictures/
arch-chroot /mnt sudo -u capote mkdir /home/capote/.secrets/
arch-chroot /mnt sudo -u capote mkdir /home/capote/Pictures/wallpapers/

# enable features on /etc/pacman.conf file
arch-chroot /mnt sed -i -e 's/#UseSyslog/UseSyslog/g' /etc/pacman.conf
arch-chroot /mnt sed -i -e 's/#Color/Color/g' /etc/pacman.conf
arch-chroot /mnt sed -i -e 's/#TotalDownload/TotalDownload/g' /etc/pacman.conf
arch-chroot /mnt sed -i -e 's/#VerbosePkgLists/VerbosePkgLists/g' /etc/pacman.conf

# enable firefox accelerated/webrender mode for quantum engine use
arch-chroot /mnt zsh -c 'echo "MOZ_ACCELERATED=1" >> /etc/environment'
arch-chroot /mnt zsh -c 'echo "MOZ_WEBRENDER=1" >> /etc/environment'

# unmounting all mounted partitions
umount -R /mnt

# syncing disks
sync

echo ""
echo "INSTALLATION COMPLETE! enjoy :)"
echo ""

sleep 3
