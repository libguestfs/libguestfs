# guestfish bash completion script
# Copyright (C) 2010 Red Hat Inc.
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
# ~/.guestfish-bash-completion.sh and add this to your .bashrc:
#   source ~/.guestfish-bash-completion.sh

# This was "inspired" by the git bash completion script written by
# Shawn O. Pearce.

_guestfish_virsh_list ()
{
    local flag_ro=$1 flags

    if [ "$flag_ro" -eq 1 ]; then
        flags="--all"
    else
        flags="--inactive"
    fi
    virsh list $flags | head -n -1 | tail -n +3 | awk '{print $2}'
}

_guestfish ()
{
    local flag_i=0 flag_ro=0 c=1 word cmds doms

    # See if user has specified -i option before the current word.
    while [ $c -lt $COMP_CWORD ]; do
        word="${COMP_WORDS[c]}"
        case "$word" in
            -i|--inspector) flag_i=1 ;;
            -r|--ro) flag_ro=1 ;;
        esac
        c=$((++c))
    done

    # Now try to complete the current word.
    word="${COMP_WORDS[COMP_CWORD]}"
    case "$word" in
        --*)
            COMPREPLY=(${COMPREPLY[@]:-} $(compgen -W '
                          --cmd-help
                          --add
                          --no-dest-paths
                          --file
                          --inspector
                          --listen
                          --mount
                          --no-sync
                          --new
                          --remote
                          --ro
                          --selinux
                          --verbose
                          --version
                        ' -- "$word")) ;;
        *)
            if [ "$flag_i" -eq 1 ]; then
                doms=$(_guestfish_virsh_list "$flag_ro")
                COMPREPLY=(${COMPREPLY[@]:-} $(compgen -W "$doms" -- "$word"))
            else
                cmds=$(guestfish -h| head -n -1 | tail -n +2 | awk '{print $1}')
                COMPREPLY=(${COMPREPLY[@]:-} $(compgen -W "$cmds" -- "$word"))
            fi ;;
    esac
}

complete -o bashdefault -o default -F _guestfish guestfish 2>/dev/null \
  || complete -o default -F _guestfish guestfish

# EOF
