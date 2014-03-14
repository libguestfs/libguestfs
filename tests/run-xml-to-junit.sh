#!/bin/sh

if [ $# -lt 2 ]; then
  echo "$0: output-of-run destination-xml"
  exit 1
fi

set -e

infile=$1
outfile=$2
owndir=`dirname $0`
ownname=`basename $0`
tmpfile=`mktemp --tmpdir $ownname.XXXXXXXXXX`

(
  echo '<?xml version="1.0" encoding="UTF-8"?>';
  echo '<tests>';
  cat $infile;
  echo '</tests>'
) > $tmpfile

xsltproc --encoding UTF-8 $owndir/run-xml-to-junit.xsl $tmpfile > $outfile
unlink $tmpfile
