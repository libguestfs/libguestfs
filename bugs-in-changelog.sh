#!/bin/bash -
# bugs-in-changelog.sh
# Copyright (C) 2009-2010 Red Hat Inc.
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

# Used when preparing the RELEASE-NOTES file.  This script looks at
# the bugs noted in the git changelog since the last stable release
# (or any release).  To use it, the only parameter should be the git
# commit range, eg:
#
#   ./bugs-in-changelog.sh "1.0.89.."

if [ -z "$1" ]; then
    echo "$0 git-commit-range"
    exit 1
fi

# Comma-separated list of Bugzilla IDs.
bugids=$(
    git log "$1" | egrep -o 'RHBZ#[0-9]+' |
    sed 's/RHBZ#//' |
    sort -u |
    tr '\n' ',' |
    sed 's/,$//'
)

#echo bugids "$bugids"

# Filter out any bugs which may still be in NEW or ASSIGNED:
bugzilla query -b "$bugids" \
    -t MODIFIED,POST,ON_QA,PASSES_QA,VERIFIED,RELEASE_PENDING,CLOSED \
    --outputformat=' - %{bug_id} %{short_desc}' |
    sort -n -r
