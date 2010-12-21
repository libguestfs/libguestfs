#!/bin/sh -

eval "$(guestfish --ro -a "$1" --i --listen)"
root="$(guestfish --remote inspect-get-roots)"
guestfish --remote inspect-get-product-name "$root"
guestfish --remote exit
