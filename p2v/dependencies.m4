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

  dnl The hwdata package contains PCI IDs, used by virt-p2v to display
  dnl network vendor information (RHBZ#855059).
  hwdata

  dnl X11 environment
  /usr/bin/xinit
  /usr/bin/Xorg
  xorg-x11-drivers
  xorg-x11-fonts-Type1
  mesa-dri-drivers
  metacity

  NetworkManager
  nm-connection-editor
  network-manager-applet
  dbus-x11        dnl required by nm-applet, but not a dependency in Fedora

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
  hwdata
  xorg
  xserver-xorg-video-all
  metacity
  network-manager
  network-manager-gnome
  network-manager-applet
  dbus-x11
)

ifelse(ARCHLINUX,1,
  pcre
  libxml2
  gtk2
  openssh
  qemu
  curl
  ethtool
  hwdata
  xorg-xinit
  xorg-server
  xf86-video-*
  metacity
  NetworkManager
  nm-connection-editor
  network-manager-applet
  dbus-x11
)

ifelse(SUSE,1,
  pcre
  libxml2
  gtk2
  /usr/bin/ssh
  /usr/bin/qemu-nbd
  curl
  ethtool
  hwdata
  /usr/bin/xinit
  /usr/bin/Xorg
  xf86-video-*
  metacity
  NetworkManager
  nm-connection-editor
  network-manager-applet
  dbus-x11
)
