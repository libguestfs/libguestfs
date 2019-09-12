# -*- python -*-
# oVirt or RHV upload create VM used by ‘virt-v2v -o rhv-upload’
# Copyright (C) 2018 Red Hat Inc.
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
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

import json
import logging
import sys
import time

from http.client import HTTPSConnection
from urllib.parse import urlparse

import ovirtsdk4 as sdk
import ovirtsdk4.types as types

# Parameters are passed in via a JSON doc from the OCaml code.
# Because this Python code ships embedded inside virt-v2v there
# is no formal API here.
params = None
ovf = None                      # OVF file

if len(sys.argv) != 3:
    raise RuntimeError("incorrect number of parameters")

# Parameters are passed in via a JSON document.
with open(sys.argv[1], 'r') as fp:
    params = json.load(fp)

# What is passed in is a password file, read the actual password.
with open(params['output_password'], 'r') as fp:
    output_password = fp.read()
output_password = output_password.rstrip()

# Read the OVF document.
with open(sys.argv[2], 'r') as fp:
    ovf = fp.read()

# Parse out the username from the output_conn URL.
parsed = urlparse(params['output_conn'])
username = parsed.username or "admin@internal"

# Connect to the server.
connection = sdk.Connection(
    url = params['output_conn'],
    username = username,
    password = output_password,
    ca_file = params['rhv_cafile'],
    log = logging.getLogger(),
    insecure = params['insecure'],
)

system_service = connection.system_service()

# Get the cluster.
cluster = system_service.clusters_service().cluster_service(params['rhv_cluster_uuid'])
cluster = cluster.get()

vms_service = system_service.vms_service()
vm = vms_service.add(
    types.Vm(
        cluster=cluster,
        initialization=types.Initialization(
            configuration = types.Configuration(
                type = types.ConfigurationType.OVA,
                data = ovf,
            )
        )
    )
)
