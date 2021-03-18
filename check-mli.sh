#!/bin/bash -
# Check every .ml file has a corresponding .mli file.
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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

# OCaml itself doesn't require it, but getting Makefile dependencies
# correct is impossible when some .ml files don't have a corresponding
# .mli file.

exitcode=0

for f in $(
    find -name '*.ml' |
    grep -v builder/templates |
    grep -v contrib/ |
    grep -v ocaml/examples/ |
    grep -v ocaml/t/ |
    grep -v 'bindtests.ml$' |
    grep -v '_tests.ml$' |
    sort
); do
    if [ ! -f "${f}i" ]; then
        echo $f: missing ${f}i
        exitcode=1
    fi
done

exit $exitcode
