dnl This is the list of distro packages which are required by
dnl virt-p2v.
dnl
dnl This file is processed by m4 with only one of the following
dnl symbols defined (depending on the target distro):
dnl
dnl   REDHAT=1     Fedora, RHEL, CentOS, SL and workalikes
dnl   DEBIAN=1     Debian and Ubuntu
dnl   ARCHLINUX=1  Arch Linux
dnl   SUSE=1       SUSE, OpenSUSE
dnl
dnl NB 1: Must be one package name per line.  Blank lines are ignored.
dnl
dnl NB 2: This works differently from appliance/packagelist.in
dnl because we don't care about the current DISTRO (the one on
dnl which libguestfs is being compiled), since we can "cross-build"
dnl the virt-p2v ISO to any other Linux distro.
dnl
dnl NB 3: libguestfs is not a dependency of virt-p2v.  libguestfs
dnl only runs on the virt-v2v conversion server.

ifelse(REDHAT,1,
  dnl Used by the virt-p2v binary.
  pcre
  libxml2
  gtk2

  dnl Run as external programs by the p2v binary.
  /usr/bin/ssh
  /usr/bin/qemu-nbd
  curl
  ethtool
  util-linux

  dnl The hwdata package contains PCI IDs, used by virt-p2v to display
  dnl network vendor information (RHBZ#855059).
  hwdata

  dnl Useful disk and diagnostic utilities.
  pciutils
  hdparm
  smartmontools

  dnl X11 environment
  xterm
  /usr/bin/xinit
  /usr/bin/Xorg
  xorg-x11-drivers
  xorg-x11-fonts-Type1
  dejavu-sans-fonts
  dejavu-sans-mono-fonts
  mesa-dri-drivers
  metacity

  NetworkManager
  nm-connection-editor
  network-manager-applet
  dnl dbus is required by nm-applet, but not a dependency in Fedora
  dbus-x11
  dnl sysadmins prefer ifconfig
  net-tools

  dnl RHBZ#1157679
  @hardware-support
)

ifelse(DEBIAN,1,
  libpcre3
  libxml2
  libgtk2.0-0
  openssh-client
  qemu-utils
  curl
  ethtool
  util-linux
  hwdata
  pciutils
  hdparm
  smartmontools
  xorg
  xterm
  xserver-xorg-video-all
  fonts-dejavu
  metacity
  network-manager
  network-manager-gnome
  network-manager-applet
  dbus-x11
  net-tools
)

ifelse(ARCHLINUX,1,
  pcre
  libxml2
  gtk2
  openssh
  qemu
  curl
  ethtool
  util-linux
  hwdata
  pciutils
  hdparm
  smartmontools
  xterm
  xorg-xinit
  xorg-server
  xf86-video-*
  ttf-dejavu
  metacity
  NetworkManager
  nm-connection-editor
  network-manager-applet
  dbus-x11
  net-tools
)

ifelse(SUSE,1,
  pcre
  libxml2
  gtk2
  qemu-tools
  openssh
  curl
  ethtool
  util-linux
  hwdata
  pciutils
  hdparm
  smartmontools
  xinit
  xorg-x11-server
  xterm
  xf86-video-*
  dejavu-fonts
  NetworkManager
  xf86-input-*
  icewm-lite
  dbus-1-x11
  yast2-network
  libyui-qt
  SuSEfirewall2
)
