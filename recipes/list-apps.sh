#!/bin/sh -

eval "$(guestfish --ro -a "$1" --i --listen)"
root="$(guestfish --remote inspect-get-roots)"
guestfish --remote inspect-list-applications "$root"
guestfish --remote exit
