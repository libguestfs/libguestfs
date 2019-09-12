# -*- python -*-
# oVirt or RHV pre-upload checks used by ‘virt-v2v -o rhv-upload’
# Copyright (C) 2018-2019 Red Hat Inc.
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

if len(sys.argv) != 2:
    raise RuntimeError("incorrect number of parameters")

# Parameters are passed in via a JSON document.
with open(sys.argv[1], 'r') as fp:
    params = json.load(fp)

# What is passed in is a password file, read the actual password.
with open(params['output_password'], 'r') as fp:
    output_password = fp.read()
output_password = output_password.rstrip()

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

# Check whether there is a datacenter for the specified storage.
data_centers = system_service.data_centers_service().list(
    search='storage.name=%s' % params['output_storage'],
    case_sensitive=True,
)
if len(data_centers) == 0:
    # The storage domain is not attached to a datacenter
    # (shouldn't happen, would fail on disk creation).
    raise RuntimeError("The storage domain ‘%s’ is not attached to a DC" %
                       (params['output_storage']))
datacenter = data_centers[0]

# Get the storage domain.
storage_domains = connection.follow_link(datacenter.storage_domains)
storage_domain = [sd for sd in storage_domains if sd.name == params['output_storage']][0]

# Get the cluster.
clusters = connection.follow_link(datacenter.clusters)
clusters = [cluster for cluster in clusters if cluster.name == params['rhv_cluster']]
if len(clusters) == 0:
    raise RuntimeError("The cluster ‘%s’ is not part of the DC ‘%s’, "
                       "where the storage domain ‘%s’ is" %
                       (params['rhv_cluster'], datacenter.name,
                        params['output_storage']))
cluster = clusters[0]

# Otherwise everything is OK, print a JSON with the results.
results = {
  "rhv_storagedomain_uuid": storage_domain.id,
  "rhv_cluster_uuid": cluster.id,
}

json.dump(results, sys.stdout)
