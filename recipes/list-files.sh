#!/bin/sh -

guestfish --ro -a "$1" -i find0 / - |
  tr '\000' '\n' |
  sort
