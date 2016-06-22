#!/bin/bash
#================
# FILE          : config.sh
#----------------
# PROJECT       : OpenSuSE KIWI Image System
# COPYRIGHT     : (c) 2006 SUSE LINUX Products GmbH. All rights reserved
#               :
# AUTHOR        : Marcus Schaefer <ms@suse.de>
#======================================
# Functions...
#--------------------------------------
test -f /.kconfig && . /.kconfig
test -f /.profile && . /.profile

#======================================
# Greeting...
#--------------------------------------
echo "Configure image: [$kiwi_iname]..."

#======================================
# Mount system filesystems
#--------------------------------------
baseMount

#======================================
# Setup baseproduct link
#--------------------------------------
suseSetupProduct

#======================================
# Add missing gpg keys to rpm
#--------------------------------------
suseImportBuildKey

#======================================
# Activate services
#--------------------------------------
suseInsertService p2v

#======================================
# Setup default target, multi-user
#--------------------------------------
baseSetRunlevel 3

#==========================================
# remove package docs
#------------------------------------------
rm -rf /usr/share/doc/packages/*
rm -rf /usr/share/doc/manual/*
rm -rf /opt/kde*

# Update the default getty target to login automatically as root without
# prompting for a password
sed -i 's/^ExecStart=\(.*\)/ExecStart=\1 -a root/' \
    /usr/lib/systemd/system/getty@.service

# Reserve tty1 as a getty so we can document it clearly
echo ReserveVT=1 >> /etc/systemd/logind.conf

sed -i 's/^ROOT_USES_LANG=.*$/ROOT_USES_LANG="yes"/' \
    /etc/sysconfig/language

#======================================
# SuSEconfig
#--------------------------------------
suseConfig

#======================================
# Umount kernel filesystems
#--------------------------------------
baseCleanMount

exit 0
