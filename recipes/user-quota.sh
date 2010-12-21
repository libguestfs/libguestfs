#!/bin/sh -

vmfile="$1"
dir=/home

eval $(guestfish --ro -a "$vmfile" -i --listen)

for d in $(guestfish --remote ls "$dir"); do
    echo -n "$dir/$d"
    echo -ne '\t'
    guestfish --remote du "$dir/$d";
done | sort -nr -k 2
guestfish --remote exit
