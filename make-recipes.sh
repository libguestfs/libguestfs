#!/bin/sh -
# libguestfs
# Copyright (C) 2009 Red Hat Inc.
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

cat <<EOF
<html>
  <head>
    <title>guestfish recipes</title>
    <link rel="stylesheet" href="recipes.css" type="text/css" title="Standard"/>
  </head>
  <body>
    <h1>guestfish recipes</h1>
    <p>You can also find these in the
    <a href="http://git.et.redhat.com/?p=libguestfs.git;a=tree;f=recipes;hb=HEAD"><code>recipes/</code>
    subdirectory</a> of the source.</p>

    <p>
    <a href="http://libguestfs.org/download/">Download
    libguestfs and guestfish here</a> or
    <a href="http://libguestfs.org/">go to the
    libguestfs home page</a>.
    </p>

    <h2>Table of recipes</h2>
    <ul>
EOF

for f in recipes/*.sh; do
    b=`basename $f .sh`
    echo -n '    <li> <a href="#'$b'">'$b.sh
    if [ -r recipes/$b.title ]; then
        echo -n ': '
        cat recipes/$b.title
    fi
    echo '</a> </li>'
done
echo '    </ul>'
echo
echo

for f in recipes/*.sh; do
    b=`basename $f .sh`
    echo -n '<a name="'$b'"></a>'
    echo -n '<h2>'$b'.sh'
    if [ -r recipes/$b.title ]; then
        echo -n ': '
        cat recipes/$b.title
    fi
    echo -n '<small style="font-size: 8pt; margin-left: 2em;"><a href="#'$b'">permalink</a></small>'
    echo '</h2>'
    if [ -r recipes/$b.html ]; then
        cat recipes/$b.html
    fi
    echo '<h3>'$b'.sh</h3>'
    echo '<pre class="example">'
    sed -e 's,&,\&amp;,g' -e 's,<,\&lt;,g' -e 's,>,\&gt;,g' < $f
    echo '</pre>'
    if [ -r recipes/$b.example ]; then
        echo '<h3>Example output</h3>'
        echo '<pre>'
        sed -e 's,&,\&amp;,g' -e 's,<,\&lt;,g' -e 's,>,\&gt;,g' < recipes/$b.example
        echo '</pre>'
    fi
done

echo '</body></html>'
