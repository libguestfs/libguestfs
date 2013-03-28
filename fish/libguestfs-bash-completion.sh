# guestfish, guestmount and libguestfs tools bash completion script
# Copyright (C) 2010-2013 Red Hat Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# To use this script, copy it into /etc/bash_completion.d/ if
# that directory exists.
#
# If your distro does not have that directory (or if you cannot or
# do not want to install this in /etc) then you can copy this to
# somewhere in your home directory such as
# ~/.libguestfs-bash-completion.sh and add this to your .bashrc:
#   source ~/.libguestfs-bash-completion.sh

# This was "inspired" by the git bash completion script written by
# Shawn O. Pearce.

_guestfs_complete ()
{
    local fn="$1" cmd="$2"
    complete -o bashdefault -o default -F "$fn" "$cmd" 2>/dev/null \
        || complete -o default -F "$fn" "$cmd"
}

# List all local libvirt domains.
_guestfs_virsh_list ()
{
    local flag_ro=$1 flags

    if [ "$flag_ro" -eq 1 ]; then
        flags="--all"
    else
        flags="--inactive"
    fi
    virsh list $flags | head -n -1 | tail -n +3 | awk '{print $2}'
}

# guestfish
_guestfs_guestfish ()
{
    local longopts flag_a=0 flag_d=0 flag_ro=0 c=1 word cmds doms

    longopts="$(guestfish --long-options)"

    # See if user has specified certain options anywhere on the
    # command line before the current word.
    while [ $c -lt $COMP_CWORD ]; do
        word="${COMP_WORDS[c]}"
        case "$word" in
            -r|--ro) flag_ro=1 ;;
        esac
        c=$((++c))
    done

    # Check for flags preceeding the current position.
    c=$(($COMP_CWORD-1))
    if [ "$c" -gt 0 ]; then
        word="${COMP_WORDS[$c]}"
        case "$word" in
            -a|--add) flag_a=1 ;;
            -d|--domain) flag_d=1 ;;
        esac
    fi

    # Now try to complete the current word.
    word="${COMP_WORDS[COMP_CWORD]}"
    case "$word" in
        --*)
            # --options
            COMPREPLY=(${COMPREPLY[@]:-} $(compgen -W "$longopts" -- "$word")) ;;
        *)
            if [ "$flag_d" -eq 1 ]; then
                # -d <domain>
                doms=$(_guestfs_virsh_list "$flag_ro")
                COMPREPLY=(${COMPREPLY[@]:-} $(compgen -W "$doms" -- "$word"))
            elif [ "$flag_a" -eq 1 ]; then
                # -a <file>
                COMPREPLY=(${COMPREPLY[@]:-} $(compgen "$word"))
            else
                # A guestfish command.
                cmds=$(guestfish -h| head -n -1 | tail -n +2 | awk '{print $1}')
                COMPREPLY=(${COMPREPLY[@]:-} $(compgen -W "$cmds" -- "$word"))
            fi ;;
    esac
}

_guestfs_complete _guestfs_guestfish guestfish

# guestmount
_guestfs_guestmount ()
{
    local longopts flag_d=0 flag_ro=0 c=1 word doms

    longopts="$(guestmount --long-options)"

    # See if user has specified certain options anywhere on the
    # command line before the current word.
    while [ $c -lt $COMP_CWORD ]; do
        word="${COMP_WORDS[c]}"
        case "$word" in
            -r|--ro) flag_ro=1 ;;
        esac
        c=$((++c))
    done

    # Check for flags preceeding the current position.
    c=$(($COMP_CWORD-1))
    if [ "$c" -gt 0 ]; then
        word="${COMP_WORDS[$c]}"
        case "$word" in
            -d|--domain) flag_d=1 ;;
        esac
    fi

    # Now try to complete the current word.
    word="${COMP_WORDS[COMP_CWORD]}"
    case "$word" in
        --*)
            # --options
            COMPREPLY=(${COMPREPLY[@]:-} $(compgen -W "$longopts" -- "$word")) ;;
        *)
            if [ "$flag_d" -eq 1 ]; then
                # -d <domain>
                doms=$(_guestfs_virsh_list "$flag_ro")
                COMPREPLY=(${COMPREPLY[@]:-} $(compgen -W "$doms" -- "$word"))
            else
                COMPREPLY=(${COMPREPLY[@]:-} $(compgen "$word"))
            fi ;;
    esac
}

_guestfs_complete _guestfs_guestmount guestmount

# virt-rescue (similar to guestmount)
_guestfs_virt_rescue ()
{
    local longopts flag_d=0 flag_ro=0 c=1 word doms

    longopts="$(virt-rescue --long-options)"

    # See if user has specified certain options anywhere on the
    # command line before the current word.
    while [ $c -lt $COMP_CWORD ]; do
        word="${COMP_WORDS[c]}"
        case "$word" in
            -r|--ro) flag_ro=1 ;;
        esac
        c=$((++c))
    done

    # Check for flags preceeding the current position.
    c=$(($COMP_CWORD-1))
    if [ "$c" -gt 0 ]; then
        word="${COMP_WORDS[$c]}"
        case "$word" in
            -d|--domain) flag_d=1 ;;
        esac
    fi

    # Now try to complete the current word.
    word="${COMP_WORDS[COMP_CWORD]}"
    case "$word" in
        --*)
            # --options
            COMPREPLY=(${COMPREPLY[@]:-} $(compgen -W "$longopts" -- "$word")) ;;
        *)
            if [ "$flag_d" -eq 1 ]; then
                # -d <domain>
                doms=$(_guestfs_virsh_list "$flag_ro")
                COMPREPLY=(${COMPREPLY[@]:-} $(compgen -W "$doms" -- "$word"))
            else
                COMPREPLY=(${COMPREPLY[@]:-} $(compgen "$word"))
            fi ;;
    esac
}

_guestfs_complete _guestfs_virt_rescue virt-rescue

# Tools like virt-cat, virt-edit etc which have an implicit --ro or --rw.
_guestfs_virttools ()
{
    local longopts="$1" flag_ro="$2" flag_d=0 c word doms

    # Check for flags preceeding the current position.
    c=$(($COMP_CWORD-1))
    if [ "$c" -gt 0 ]; then
        word="${COMP_WORDS[$c]}"
        case "$word" in
            -d|--domain) flag_d=1 ;;
        esac
    fi

    # Now try to complete the current word.
    word="${COMP_WORDS[COMP_CWORD]}"
    case "$word" in
        --*)
            # --options
            COMPREPLY=(${COMPREPLY[@]:-} $(compgen -W "$longopts" -- "$word")) ;;
        *)
            if [ "$flag_d" -eq 1 ]; then
                # -d <domain>
                doms=$(_guestfs_virsh_list "$flag_ro")
                COMPREPLY=(${COMPREPLY[@]:-} $(compgen -W "$doms" -- "$word"))
            else
                COMPREPLY=(${COMPREPLY[@]:-} $(compgen "$word"))
            fi ;;
    esac
}

_guestfs_virt_alignment_scan ()
{
    _guestfs_virttools "$(virt-alignment-scan --long-options)" 1
}

_guestfs_complete _guestfs_virt_alignment_scan virt-alignment-scan

_guestfs_virt_cat ()
{
    _guestfs_virttools "$(virt-cat --long-options)" 1
}

_guestfs_complete _guestfs_virt_cat virt-cat

_guestfs_virt_df ()
{
    _guestfs_virttools "$(virt-df --long-options)" 1
}

_guestfs_complete _guestfs_virt_df virt-df

_guestfs_virt_edit ()
{
    _guestfs_virttools "$(virt-edit --long-options)" 0
}

_guestfs_complete _guestfs_virt_edit virt-edit

_guestfs_virt_filesystems ()
{
    _guestfs_virttools "$(virt-filesystems --long-options)" 1
}

_guestfs_complete _guestfs_virt_filesystems virt-filesystems

_guestfs_virt_format ()
{
    _guestfs_virttools "$(virt-format --long-options)" 0
}

_guestfs_complete _guestfs_virt_format virt-format

_guestfs_virt_inspector ()
{
    _guestfs_virttools "$(virt-inspector --long-options)" 1
}

_guestfs_complete _guestfs_virt_inspector virt-inspector

_guestfs_virt_ls ()
{
    _guestfs_virttools "$(virt-ls --long-options)" 1
}

_guestfs_complete _guestfs_virt_ls virt-ls

_guestfs_virt_sysprep ()
{
    _guestfs_virttools "$(virt-sysprep --long-options)" 0
}

_guestfs_complete _guestfs_virt_sysprep virt-sysprep

# Where we can only complete --options.
_guestfs_options_only ()
{
    local longopts="$1" word

    # Try to complete the current word.
    word="${COMP_WORDS[COMP_CWORD]}"
    case "$word" in
        --*)
            # --options
            COMPREPLY=(${COMPREPLY[@]:-} $(compgen -W "$longopts" -- "$word")) ;;
        *)
            COMPREPLY=(${COMPREPLY[@]:-} $(compgen "$word"))
    esac
}

_guestfs_virt_resize ()
{
    _guestfs_options_only "$(virt-resize --long-options)"
}

_guestfs_complete _guestfs_virt_resize virt-resize

_guestfs_virt_sparsify ()
{
    _guestfs_options_only "$(virt-sparsify --long-options)"
}

_guestfs_complete _guestfs_virt_sparsify virt-sparsify

# Not done:
# - virt-copy-in
# - virt-copy-out
# - virt-list-filesystems
# - virt-list-partitions
# - virt-make-fs
# - virt-tar
# - virt-tar-in
# - virt-tar-out
# - virt-win-reg

# EOF
