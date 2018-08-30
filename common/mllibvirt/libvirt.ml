(* OCaml bindings for libvirt.
   (C) Copyright 2007-2015 Richard W.M. Jones, Red Hat Inc.
   https://libvirt.org/

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version,
   with the OCaml linking exception described in ../COPYING.LIB.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free Software
   Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
*)

type uuid = string

type xml = string

type filename = string

external get_version : ?driver:string -> unit -> int * int = "ocaml_libvirt_get_version"

let uuid_length = 16
let uuid_string_length = 36

(* https://caml.inria.fr/pub/ml-archives/caml-list/2004/07/80683af867cce6bf8fff273973f70c95.en.html *)
type rw = [`R|`W]
type ro = [`R]

module Connect =
struct
  type 'rw t

  type node_info = {
    model : string;
    memory : int64;
    cpus : int;
    mhz : int;
    nodes : int;
    sockets : int;
    cores : int;
    threads : int;
  }

  type credential_type =
    | CredentialUsername
    | CredentialAuthname
    | CredentialLanguage
    | CredentialCnonce
    | CredentialPassphrase
    | CredentialEchoprompt
    | CredentialNoechoprompt
    | CredentialRealm
    | CredentialExternal

  type credential = {
    typ : credential_type;
    prompt : string;
    challenge : string option;
    defresult : string option;
  }

  type auth = {
    credtype : credential_type list;
    cb : (credential list -> string option list);
  }

  type list_flag =
    | ListNoState | ListRunning | ListBlocked
    | ListPaused | ListShutdown | ListShutoff | ListCrashed
    | ListActive
    | ListInactive
    | ListAll

  external connect : ?name:string -> unit -> rw t = "ocaml_libvirt_connect_open"
  external connect_readonly : ?name:string -> unit -> ro t = "ocaml_libvirt_connect_open_readonly"
  external connect_auth : ?name:string -> auth -> rw t = "ocaml_libvirt_connect_open_auth"
  external connect_auth_readonly : ?name:string -> auth -> ro t = "ocaml_libvirt_connect_open_auth_readonly"
  external close : [>`R] t -> unit = "ocaml_libvirt_connect_close"
  external get_type : [>`R] t -> string = "ocaml_libvirt_connect_get_type"
  external get_version : [>`R] t -> int = "ocaml_libvirt_connect_get_version"
  external get_hostname : [>`R] t -> string = "ocaml_libvirt_connect_get_hostname"
  external get_uri : [>`R] t -> string = "ocaml_libvirt_connect_get_uri"
  external get_max_vcpus : [>`R] t -> ?type_:string -> unit -> int = "ocaml_libvirt_connect_get_max_vcpus"
  external list_domains : [>`R] t -> int -> int array = "ocaml_libvirt_connect_list_domains"
  external num_of_domains : [>`R] t -> int = "ocaml_libvirt_connect_num_of_domains"
  external get_capabilities : [>`R] t -> xml = "ocaml_libvirt_connect_get_capabilities"
  external num_of_defined_domains : [>`R] t -> int = "ocaml_libvirt_connect_num_of_defined_domains"
  external list_defined_domains : [>`R] t -> int -> string array = "ocaml_libvirt_connect_list_defined_domains"
  external num_of_networks : [>`R] t -> int = "ocaml_libvirt_connect_num_of_networks"
  external list_networks : [>`R] t -> int -> string array = "ocaml_libvirt_connect_list_networks"
  external num_of_defined_networks : [>`R] t -> int = "ocaml_libvirt_connect_num_of_defined_networks"
  external list_defined_networks : [>`R] t -> int -> string array = "ocaml_libvirt_connect_list_defined_networks"
  external num_of_pools : [>`R] t -> int = "ocaml_libvirt_connect_num_of_storage_pools"
  external list_pools : [>`R] t -> int -> string array = "ocaml_libvirt_connect_list_storage_pools"
  external num_of_defined_pools : [>`R] t -> int = "ocaml_libvirt_connect_num_of_defined_storage_pools"
  external list_defined_pools : [>`R] t -> int -> string array = "ocaml_libvirt_connect_list_defined_storage_pools"
  external num_of_secrets : [>`R] t -> int = "ocaml_libvirt_connect_num_of_secrets"
  external list_secrets : [>`R] t -> int -> string array = "ocaml_libvirt_connect_list_secrets"

  external get_node_info : [>`R] t -> node_info = "ocaml_libvirt_connect_get_node_info"
  external node_get_free_memory : [> `R] t -> int64 = "ocaml_libvirt_connect_node_get_free_memory"
  external node_get_cells_free_memory : [> `R] t -> int -> int -> int64 array = "ocaml_libvirt_connect_node_get_cells_free_memory"

  (* See VIR_NODEINFO_MAXCPUS macro defined in <libvirt.h>. *)
  let maxcpus_of_node_info { nodes = nodes; sockets = sockets;
			     cores = cores; threads = threads } =
    nodes * sockets * cores * threads

  (* See VIR_CPU_MAPLEN macro defined in <libvirt.h>. *)
  let cpumaplen nr_cpus =
    (nr_cpus + 7) / 8

  (* See VIR_USE_CPU, VIR_UNUSE_CPU, VIR_CPU_USABLE macros defined in <libvirt.h>. *)
  let use_cpu cpumap cpu =
    Bytes.set cpumap (cpu/8)
      (Char.chr (Char.code (Bytes.get cpumap (cpu/8)) lor (1 lsl (cpu mod 8))))
  let unuse_cpu cpumap cpu =
    Bytes.set cpumap (cpu/8)
      (Char.chr (Char.code (Bytes.get cpumap (cpu/8)) land (lnot (1 lsl (cpu mod 8)))))
  let cpu_usable cpumaps maplen vcpu cpu =
    Char.code (Bytes.get cpumaps (vcpu*maplen + cpu/8)) land (1 lsl (cpu mod 8)) <> 0

  external set_keep_alive : [>`R] t -> int -> int -> unit = "ocaml_libvirt_connect_set_keep_alive"

  (* Internal API needed for get_auth_default. *)
  external _credtypes_from_auth_default : unit -> credential_type list = "ocaml_libvirt_connect_credtypes_from_auth_default"
  external _call_auth_default_callback : credential list -> string option list = "ocaml_libvirt_connect_call_auth_default_callback"
  let get_auth_default () =
    {
      credtype = _credtypes_from_auth_default ();
      cb = _call_auth_default_callback;
    }

  external get_domain_capabilities : ?emulatorbin:string -> ?arch:string -> ?machine:string -> ?virttype:string -> [>`R] t -> string = "ocaml_libvirt_connect_get_domain_capabilities"

  external const : [>`R] t -> ro t = "%identity"
end

module Virterror =
struct
  type code =
    | VIR_ERR_OK
    | VIR_ERR_INTERNAL_ERROR
    | VIR_ERR_NO_MEMORY
    | VIR_ERR_NO_SUPPORT
    | VIR_ERR_UNKNOWN_HOST
    | VIR_ERR_NO_CONNECT
    | VIR_ERR_INVALID_CONN
    | VIR_ERR_INVALID_DOMAIN
    | VIR_ERR_INVALID_ARG
    | VIR_ERR_OPERATION_FAILED
    | VIR_ERR_GET_FAILED
    | VIR_ERR_POST_FAILED
    | VIR_ERR_HTTP_ERROR
    | VIR_ERR_SEXPR_SERIAL
    | VIR_ERR_NO_XEN
    | VIR_ERR_XEN_CALL
    | VIR_ERR_OS_TYPE
    | VIR_ERR_NO_KERNEL
    | VIR_ERR_NO_ROOT
    | VIR_ERR_NO_SOURCE
    | VIR_ERR_NO_TARGET
    | VIR_ERR_NO_NAME
    | VIR_ERR_NO_OS
    | VIR_ERR_NO_DEVICE
    | VIR_ERR_NO_XENSTORE
    | VIR_ERR_DRIVER_FULL
    | VIR_ERR_CALL_FAILED
    | VIR_ERR_XML_ERROR
    | VIR_ERR_DOM_EXIST
    | VIR_ERR_OPERATION_DENIED
    | VIR_ERR_OPEN_FAILED
    | VIR_ERR_READ_FAILED
    | VIR_ERR_PARSE_FAILED
    | VIR_ERR_CONF_SYNTAX
    | VIR_ERR_WRITE_FAILED
    | VIR_ERR_XML_DETAIL
    | VIR_ERR_INVALID_NETWORK
    | VIR_ERR_NETWORK_EXIST
    | VIR_ERR_SYSTEM_ERROR
    | VIR_ERR_RPC
    | VIR_ERR_GNUTLS_ERROR
    | VIR_WAR_NO_NETWORK
    | VIR_ERR_NO_DOMAIN
    | VIR_ERR_NO_NETWORK
    | VIR_ERR_INVALID_MAC
    | VIR_ERR_AUTH_FAILED
    | VIR_ERR_INVALID_STORAGE_POOL
    | VIR_ERR_INVALID_STORAGE_VOL
    | VIR_WAR_NO_STORAGE
    | VIR_ERR_NO_STORAGE_POOL
    | VIR_ERR_NO_STORAGE_VOL
    | VIR_WAR_NO_NODE
    | VIR_ERR_INVALID_NODE_DEVICE
    | VIR_ERR_NO_NODE_DEVICE
    | VIR_ERR_NO_SECURITY_MODEL
    | VIR_ERR_OPERATION_INVALID
    | VIR_WAR_NO_INTERFACE
    | VIR_ERR_NO_INTERFACE
    | VIR_ERR_INVALID_INTERFACE
    | VIR_ERR_MULTIPLE_INTERFACES
    | VIR_WAR_NO_NWFILTER
    | VIR_ERR_INVALID_NWFILTER
    | VIR_ERR_NO_NWFILTER
    | VIR_ERR_BUILD_FIREWALL
    | VIR_WAR_NO_SECRET
    | VIR_ERR_INVALID_SECRET
    | VIR_ERR_NO_SECRET
    | VIR_ERR_CONFIG_UNSUPPORTED
    | VIR_ERR_OPERATION_TIMEOUT
    | VIR_ERR_MIGRATE_PERSIST_FAILED
    | VIR_ERR_HOOK_SCRIPT_FAILED
    | VIR_ERR_INVALID_DOMAIN_SNAPSHOT
    | VIR_ERR_NO_DOMAIN_SNAPSHOT
    | VIR_ERR_INVALID_STREAM
    | VIR_ERR_ARGUMENT_UNSUPPORTED
    | VIR_ERR_STORAGE_PROBE_FAILED
    | VIR_ERR_STORAGE_POOL_BUILT
    | VIR_ERR_SNAPSHOT_REVERT_RISKY
    | VIR_ERR_OPERATION_ABORTED
    | VIR_ERR_AUTH_CANCELLED
    | VIR_ERR_NO_DOMAIN_METADATA
    | VIR_ERR_MIGRATE_UNSAFE
    | VIR_ERR_OVERFLOW
    | VIR_ERR_BLOCK_COPY_ACTIVE
    | VIR_ERR_OPERATION_UNSUPPORTED
    | VIR_ERR_SSH
    | VIR_ERR_AGENT_UNRESPONSIVE
    | VIR_ERR_RESOURCE_BUSY
    | VIR_ERR_ACCESS_DENIED
    | VIR_ERR_DBUS_SERVICE
    | VIR_ERR_STORAGE_VOL_EXIST
    | VIR_ERR_CPU_INCOMPATIBLE
    | VIR_ERR_XML_INVALID_SCHEMA
    | VIR_ERR_MIGRATE_FINISH_OK
    | VIR_ERR_AUTH_UNAVAILABLE
    | VIR_ERR_NO_SERVER
    | VIR_ERR_NO_CLIENT
    | VIR_ERR_AGENT_UNSYNCED
    | VIR_ERR_LIBSSH
    | VIR_ERR_DEVICE_MISSING
    | VIR_ERR_INVALID_NWFILTER_BINDING
    | VIR_ERR_NO_NWFILTER_BINDING
    | VIR_ERR_INVALID_DOMAIN_CHECKPOINT
    | VIR_ERR_NO_DOMAIN_CHECKPOINT
    | VIR_ERR_NO_DOMAIN_BACKUP
    | VIR_ERR_UNKNOWN of int

  let string_of_code = function
    | VIR_ERR_OK -> "VIR_ERR_OK"
    | VIR_ERR_INTERNAL_ERROR -> "VIR_ERR_INTERNAL_ERROR"
    | VIR_ERR_NO_MEMORY -> "VIR_ERR_NO_MEMORY"
    | VIR_ERR_NO_SUPPORT -> "VIR_ERR_NO_SUPPORT"
    | VIR_ERR_UNKNOWN_HOST -> "VIR_ERR_UNKNOWN_HOST"
    | VIR_ERR_NO_CONNECT -> "VIR_ERR_NO_CONNECT"
    | VIR_ERR_INVALID_CONN -> "VIR_ERR_INVALID_CONN"
    | VIR_ERR_INVALID_DOMAIN -> "VIR_ERR_INVALID_DOMAIN"
    | VIR_ERR_INVALID_ARG -> "VIR_ERR_INVALID_ARG"
    | VIR_ERR_OPERATION_FAILED -> "VIR_ERR_OPERATION_FAILED"
    | VIR_ERR_GET_FAILED -> "VIR_ERR_GET_FAILED"
    | VIR_ERR_POST_FAILED -> "VIR_ERR_POST_FAILED"
    | VIR_ERR_HTTP_ERROR -> "VIR_ERR_HTTP_ERROR"
    | VIR_ERR_SEXPR_SERIAL -> "VIR_ERR_SEXPR_SERIAL"
    | VIR_ERR_NO_XEN -> "VIR_ERR_NO_XEN"
    | VIR_ERR_XEN_CALL -> "VIR_ERR_XEN_CALL"
    | VIR_ERR_OS_TYPE -> "VIR_ERR_OS_TYPE"
    | VIR_ERR_NO_KERNEL -> "VIR_ERR_NO_KERNEL"
    | VIR_ERR_NO_ROOT -> "VIR_ERR_NO_ROOT"
    | VIR_ERR_NO_SOURCE -> "VIR_ERR_NO_SOURCE"
    | VIR_ERR_NO_TARGET -> "VIR_ERR_NO_TARGET"
    | VIR_ERR_NO_NAME -> "VIR_ERR_NO_NAME"
    | VIR_ERR_NO_OS -> "VIR_ERR_NO_OS"
    | VIR_ERR_NO_DEVICE -> "VIR_ERR_NO_DEVICE"
    | VIR_ERR_NO_XENSTORE -> "VIR_ERR_NO_XENSTORE"
    | VIR_ERR_DRIVER_FULL -> "VIR_ERR_DRIVER_FULL"
    | VIR_ERR_CALL_FAILED -> "VIR_ERR_CALL_FAILED"
    | VIR_ERR_XML_ERROR -> "VIR_ERR_XML_ERROR"
    | VIR_ERR_DOM_EXIST -> "VIR_ERR_DOM_EXIST"
    | VIR_ERR_OPERATION_DENIED -> "VIR_ERR_OPERATION_DENIED"
    | VIR_ERR_OPEN_FAILED -> "VIR_ERR_OPEN_FAILED"
    | VIR_ERR_READ_FAILED -> "VIR_ERR_READ_FAILED"
    | VIR_ERR_PARSE_FAILED -> "VIR_ERR_PARSE_FAILED"
    | VIR_ERR_CONF_SYNTAX -> "VIR_ERR_CONF_SYNTAX"
    | VIR_ERR_WRITE_FAILED -> "VIR_ERR_WRITE_FAILED"
    | VIR_ERR_XML_DETAIL -> "VIR_ERR_XML_DETAIL"
    | VIR_ERR_INVALID_NETWORK -> "VIR_ERR_INVALID_NETWORK"
    | VIR_ERR_NETWORK_EXIST -> "VIR_ERR_NETWORK_EXIST"
    | VIR_ERR_SYSTEM_ERROR -> "VIR_ERR_SYSTEM_ERROR"
    | VIR_ERR_RPC -> "VIR_ERR_RPC"
    | VIR_ERR_GNUTLS_ERROR -> "VIR_ERR_GNUTLS_ERROR"
    | VIR_WAR_NO_NETWORK -> "VIR_WAR_NO_NETWORK"
    | VIR_ERR_NO_DOMAIN -> "VIR_ERR_NO_DOMAIN"
    | VIR_ERR_NO_NETWORK -> "VIR_ERR_NO_NETWORK"
    | VIR_ERR_INVALID_MAC -> "VIR_ERR_INVALID_MAC"
    | VIR_ERR_AUTH_FAILED -> "VIR_ERR_AUTH_FAILED"
    | VIR_ERR_INVALID_STORAGE_POOL -> "VIR_ERR_INVALID_STORAGE_POOL"
    | VIR_ERR_INVALID_STORAGE_VOL -> "VIR_ERR_INVALID_STORAGE_VOL"
    | VIR_WAR_NO_STORAGE -> "VIR_WAR_NO_STORAGE"
    | VIR_ERR_NO_STORAGE_POOL -> "VIR_ERR_NO_STORAGE_POOL"
    | VIR_ERR_NO_STORAGE_VOL -> "VIR_ERR_NO_STORAGE_VOL"
    | VIR_WAR_NO_NODE -> "VIR_WAR_NO_NODE"
    | VIR_ERR_INVALID_NODE_DEVICE -> "VIR_ERR_INVALID_NODE_DEVICE"
    | VIR_ERR_NO_NODE_DEVICE -> "VIR_ERR_NO_NODE_DEVICE"
    | VIR_ERR_NO_SECURITY_MODEL -> "VIR_ERR_NO_SECURITY_MODEL"
    | VIR_ERR_OPERATION_INVALID -> "VIR_ERR_OPERATION_INVALID"
    | VIR_WAR_NO_INTERFACE -> "VIR_WAR_NO_INTERFACE"
    | VIR_ERR_NO_INTERFACE -> "VIR_ERR_NO_INTERFACE"
    | VIR_ERR_INVALID_INTERFACE -> "VIR_ERR_INVALID_INTERFACE"
    | VIR_ERR_MULTIPLE_INTERFACES -> "VIR_ERR_MULTIPLE_INTERFACES"
    | VIR_WAR_NO_NWFILTER -> "VIR_WAR_NO_NWFILTER"
    | VIR_ERR_INVALID_NWFILTER -> "VIR_ERR_INVALID_NWFILTER"
    | VIR_ERR_NO_NWFILTER -> "VIR_ERR_NO_NWFILTER"
    | VIR_ERR_BUILD_FIREWALL -> "VIR_ERR_BUILD_FIREWALL"
    | VIR_WAR_NO_SECRET -> "VIR_WAR_NO_SECRET"
    | VIR_ERR_INVALID_SECRET -> "VIR_ERR_INVALID_SECRET"
    | VIR_ERR_NO_SECRET -> "VIR_ERR_NO_SECRET"
    | VIR_ERR_CONFIG_UNSUPPORTED -> "VIR_ERR_CONFIG_UNSUPPORTED"
    | VIR_ERR_OPERATION_TIMEOUT -> "VIR_ERR_OPERATION_TIMEOUT"
    | VIR_ERR_MIGRATE_PERSIST_FAILED -> "VIR_ERR_MIGRATE_PERSIST_FAILED"
    | VIR_ERR_HOOK_SCRIPT_FAILED -> "VIR_ERR_HOOK_SCRIPT_FAILED"
    | VIR_ERR_INVALID_DOMAIN_SNAPSHOT -> "VIR_ERR_INVALID_DOMAIN_SNAPSHOT"
    | VIR_ERR_NO_DOMAIN_SNAPSHOT -> "VIR_ERR_NO_DOMAIN_SNAPSHOT"
    | VIR_ERR_INVALID_STREAM -> "VIR_ERR_INVALID_STREAM"
    | VIR_ERR_ARGUMENT_UNSUPPORTED -> "VIR_ERR_ARGUMENT_UNSUPPORTED"
    | VIR_ERR_STORAGE_PROBE_FAILED -> "VIR_ERR_STORAGE_PROBE_FAILED"
    | VIR_ERR_STORAGE_POOL_BUILT -> "VIR_ERR_STORAGE_POOL_BUILT"
    | VIR_ERR_SNAPSHOT_REVERT_RISKY -> "VIR_ERR_SNAPSHOT_REVERT_RISKY"
    | VIR_ERR_OPERATION_ABORTED -> "VIR_ERR_OPERATION_ABORTED"
    | VIR_ERR_AUTH_CANCELLED -> "VIR_ERR_AUTH_CANCELLED"
    | VIR_ERR_NO_DOMAIN_METADATA -> "VIR_ERR_NO_DOMAIN_METADATA"
    | VIR_ERR_MIGRATE_UNSAFE -> "VIR_ERR_MIGRATE_UNSAFE"
    | VIR_ERR_OVERFLOW -> "VIR_ERR_OVERFLOW"
    | VIR_ERR_BLOCK_COPY_ACTIVE -> "VIR_ERR_BLOCK_COPY_ACTIVE"
    | VIR_ERR_OPERATION_UNSUPPORTED -> "VIR_ERR_OPERATION_UNSUPPORTED"
    | VIR_ERR_SSH -> "VIR_ERR_SSH"
    | VIR_ERR_AGENT_UNRESPONSIVE -> "VIR_ERR_AGENT_UNRESPONSIVE"
    | VIR_ERR_RESOURCE_BUSY -> "VIR_ERR_RESOURCE_BUSY"
    | VIR_ERR_ACCESS_DENIED -> "VIR_ERR_ACCESS_DENIED"
    | VIR_ERR_DBUS_SERVICE -> "VIR_ERR_DBUS_SERVICE"
    | VIR_ERR_STORAGE_VOL_EXIST -> "VIR_ERR_STORAGE_VOL_EXIST"
    | VIR_ERR_CPU_INCOMPATIBLE -> "VIR_ERR_CPU_INCOMPATIBLE"
    | VIR_ERR_XML_INVALID_SCHEMA -> "VIR_ERR_XML_INVALID_SCHEMA"
    | VIR_ERR_MIGRATE_FINISH_OK -> "VIR_ERR_MIGRATE_FINISH_OK"
    | VIR_ERR_AUTH_UNAVAILABLE -> "VIR_ERR_AUTH_UNAVAILABLE"
    | VIR_ERR_NO_SERVER -> "VIR_ERR_NO_SERVER"
    | VIR_ERR_NO_CLIENT -> "VIR_ERR_NO_CLIENT"
    | VIR_ERR_AGENT_UNSYNCED -> "VIR_ERR_AGENT_UNSYNCED"
    | VIR_ERR_LIBSSH -> "VIR_ERR_LIBSSH"
    | VIR_ERR_DEVICE_MISSING -> "VIR_ERR_DEVICE_MISSING"
    | VIR_ERR_INVALID_NWFILTER_BINDING -> "VIR_ERR_INVALID_NWFILTER_BINDING"
    | VIR_ERR_NO_NWFILTER_BINDING -> "VIR_ERR_NO_NWFILTER_BINDING"
    | VIR_ERR_INVALID_DOMAIN_CHECKPOINT -> "VIR_ERR_INVALID_DOMAIN_CHECKPOINT"
    | VIR_ERR_NO_DOMAIN_CHECKPOINT -> "VIR_ERR_NO_DOMAIN_CHECKPOINT"
    | VIR_ERR_NO_DOMAIN_BACKUP -> "VIR_ERR_NO_DOMAIN_BACKUP"
    | VIR_ERR_UNKNOWN i -> "VIR_ERR_" ^ string_of_int i

  type domain =
    | VIR_FROM_NONE
    | VIR_FROM_XEN
    | VIR_FROM_XEND
    | VIR_FROM_XENSTORE
    | VIR_FROM_SEXPR
    | VIR_FROM_XML
    | VIR_FROM_DOM
    | VIR_FROM_RPC
    | VIR_FROM_PROXY
    | VIR_FROM_CONF
    | VIR_FROM_QEMU
    | VIR_FROM_NET
    | VIR_FROM_TEST
    | VIR_FROM_REMOTE
    | VIR_FROM_OPENVZ
    | VIR_FROM_XENXM
    | VIR_FROM_STATS_LINUX
    | VIR_FROM_LXC
    | VIR_FROM_STORAGE
    | VIR_FROM_NETWORK
    | VIR_FROM_DOMAIN
    | VIR_FROM_UML
    | VIR_FROM_NODEDEV
    | VIR_FROM_XEN_INOTIFY
    | VIR_FROM_SECURITY
    | VIR_FROM_VBOX
    | VIR_FROM_INTERFACE
    | VIR_FROM_ONE
    | VIR_FROM_ESX
    | VIR_FROM_PHYP
    | VIR_FROM_SECRET
    | VIR_FROM_CPU
    | VIR_FROM_XENAPI
    | VIR_FROM_NWFILTER
    | VIR_FROM_HOOK
    | VIR_FROM_DOMAIN_SNAPSHOT
    | VIR_FROM_AUDIT
    | VIR_FROM_SYSINFO
    | VIR_FROM_STREAMS
    | VIR_FROM_VMWARE
    | VIR_FROM_EVENT
    | VIR_FROM_LIBXL
    | VIR_FROM_LOCKING
    | VIR_FROM_HYPERV
    | VIR_FROM_CAPABILITIES
    | VIR_FROM_URI
    | VIR_FROM_AUTH
    | VIR_FROM_DBUS
    | VIR_FROM_PARALLELS
    | VIR_FROM_DEVICE
    | VIR_FROM_SSH
    | VIR_FROM_LOCKSPACE
    | VIR_FROM_INITCTL
    | VIR_FROM_IDENTITY
    | VIR_FROM_CGROUP
    | VIR_FROM_ACCESS
    | VIR_FROM_SYSTEMD
    | VIR_FROM_BHYVE
    | VIR_FROM_CRYPTO
    | VIR_FROM_FIREWALL
    | VIR_FROM_POLKIT
    | VIR_FROM_THREAD
    | VIR_FROM_ADMIN
    | VIR_FROM_LOGGING
    | VIR_FROM_XENXL
    | VIR_FROM_PERF
    | VIR_FROM_LIBSSH
    | VIR_FROM_RESCTRL
    | VIR_FROM_FIREWALLD
    | VIR_FROM_DOMAIN_CHECKPOINT
    | VIR_FROM_UNKNOWN of int

  let string_of_domain = function
    | VIR_FROM_NONE -> "VIR_FROM_NONE"
    | VIR_FROM_XEN -> "VIR_FROM_XEN"
    | VIR_FROM_XEND -> "VIR_FROM_XEND"
    | VIR_FROM_XENSTORE -> "VIR_FROM_XENSTORE"
    | VIR_FROM_SEXPR -> "VIR_FROM_SEXPR"
    | VIR_FROM_XML -> "VIR_FROM_XML"
    | VIR_FROM_DOM -> "VIR_FROM_DOM"
    | VIR_FROM_RPC -> "VIR_FROM_RPC"
    | VIR_FROM_PROXY -> "VIR_FROM_PROXY"
    | VIR_FROM_CONF -> "VIR_FROM_CONF"
    | VIR_FROM_QEMU -> "VIR_FROM_QEMU"
    | VIR_FROM_NET -> "VIR_FROM_NET"
    | VIR_FROM_TEST -> "VIR_FROM_TEST"
    | VIR_FROM_REMOTE -> "VIR_FROM_REMOTE"
    | VIR_FROM_OPENVZ -> "VIR_FROM_OPENVZ"
    | VIR_FROM_XENXM -> "VIR_FROM_XENXM"
    | VIR_FROM_STATS_LINUX -> "VIR_FROM_STATS_LINUX"
    | VIR_FROM_LXC -> "VIR_FROM_LXC"
    | VIR_FROM_STORAGE -> "VIR_FROM_STORAGE"
    | VIR_FROM_NETWORK -> "VIR_FROM_NETWORK"
    | VIR_FROM_DOMAIN -> "VIR_FROM_DOMAIN"
    | VIR_FROM_UML -> "VIR_FROM_UML"
    | VIR_FROM_NODEDEV -> "VIR_FROM_NODEDEV"
    | VIR_FROM_XEN_INOTIFY -> "VIR_FROM_XEN_INOTIFY"
    | VIR_FROM_SECURITY -> "VIR_FROM_SECURITY"
    | VIR_FROM_VBOX -> "VIR_FROM_VBOX"
    | VIR_FROM_INTERFACE -> "VIR_FROM_INTERFACE"
    | VIR_FROM_ONE -> "VIR_FROM_ONE"
    | VIR_FROM_ESX -> "VIR_FROM_ESX"
    | VIR_FROM_PHYP -> "VIR_FROM_PHYP"
    | VIR_FROM_SECRET -> "VIR_FROM_SECRET"
    | VIR_FROM_CPU -> "VIR_FROM_CPU"
    | VIR_FROM_XENAPI -> "VIR_FROM_XENAPI"
    | VIR_FROM_NWFILTER -> "VIR_FROM_NWFILTER"
    | VIR_FROM_HOOK -> "VIR_FROM_HOOK"
    | VIR_FROM_DOMAIN_SNAPSHOT -> "VIR_FROM_DOMAIN_SNAPSHOT"
    | VIR_FROM_AUDIT -> "VIR_FROM_AUDIT"
    | VIR_FROM_SYSINFO -> "VIR_FROM_SYSINFO"
    | VIR_FROM_STREAMS -> "VIR_FROM_STREAMS"
    | VIR_FROM_VMWARE -> "VIR_FROM_VMWARE"
    | VIR_FROM_EVENT -> "VIR_FROM_EVENT"
    | VIR_FROM_LIBXL -> "VIR_FROM_LIBXL"
    | VIR_FROM_LOCKING -> "VIR_FROM_LOCKING"
    | VIR_FROM_HYPERV -> "VIR_FROM_HYPERV"
    | VIR_FROM_CAPABILITIES -> "VIR_FROM_CAPABILITIES"
    | VIR_FROM_URI -> "VIR_FROM_URI"
    | VIR_FROM_AUTH -> "VIR_FROM_AUTH"
    | VIR_FROM_DBUS -> "VIR_FROM_DBUS"
    | VIR_FROM_PARALLELS -> "VIR_FROM_PARALLELS"
    | VIR_FROM_DEVICE -> "VIR_FROM_DEVICE"
    | VIR_FROM_SSH -> "VIR_FROM_SSH"
    | VIR_FROM_LOCKSPACE -> "VIR_FROM_LOCKSPACE"
    | VIR_FROM_INITCTL -> "VIR_FROM_INITCTL"
    | VIR_FROM_IDENTITY -> "VIR_FROM_IDENTITY"
    | VIR_FROM_CGROUP -> "VIR_FROM_CGROUP"
    | VIR_FROM_ACCESS -> "VIR_FROM_ACCESS"
    | VIR_FROM_SYSTEMD -> "VIR_FROM_SYSTEMD"
    | VIR_FROM_BHYVE -> "VIR_FROM_BHYVE"
    | VIR_FROM_CRYPTO -> "VIR_FROM_CRYPTO"
    | VIR_FROM_FIREWALL -> "VIR_FROM_FIREWALL"
    | VIR_FROM_POLKIT -> "VIR_FROM_POLKIT"
    | VIR_FROM_THREAD -> "VIR_FROM_THREAD"
    | VIR_FROM_ADMIN -> "VIR_FROM_ADMIN"
    | VIR_FROM_LOGGING -> "VIR_FROM_LOGGING"
    | VIR_FROM_XENXL -> "VIR_FROM_XENXL"
    | VIR_FROM_PERF -> "VIR_FROM_PERF"
    | VIR_FROM_LIBSSH -> "VIR_FROM_LIBSSH"
    | VIR_FROM_RESCTRL -> "VIR_FROM_RESCTRL"
    | VIR_FROM_FIREWALLD -> "VIR_FROM_FIREWALLD"
    | VIR_FROM_DOMAIN_CHECKPOINT -> "VIR_FROM_DOMAIN_CHECKPOINT"
    | VIR_FROM_UNKNOWN i -> "VIR_FROM_" ^ string_of_int i

  type level =
    | VIR_ERR_NONE
    | VIR_ERR_WARNING
    | VIR_ERR_ERROR
    | VIR_ERR_UNKNOWN_LEVEL of int

  let string_of_level = function
    | VIR_ERR_NONE -> "VIR_ERR_NONE"
    | VIR_ERR_WARNING -> "VIR_ERR_WARNING"
    | VIR_ERR_ERROR -> "VIR_ERR_ERROR"
    | VIR_ERR_UNKNOWN_LEVEL i -> "VIR_ERR_LEVEL_" ^ string_of_int i

  type t = {
    code : code;
    domain : domain;
    message : string option;
    level : level;
    str1 : string option;
    str2 : string option;
    str3 : string option;
    int1 : int32;
    int2 : int32;
  }

  let to_string { code = code; domain = domain; message = message } =
    let buf = Buffer.create 128 in
    Buffer.add_string buf "libvirt: ";
    Buffer.add_string buf (string_of_code code);
    Buffer.add_string buf ": ";
    Buffer.add_string buf (string_of_domain domain);
    Buffer.add_string buf ": ";
    (match message with Some msg -> Buffer.add_string buf msg | None -> ());
    Buffer.contents buf

  external get_last_error : unit -> t option = "ocaml_libvirt_virterror_get_last_error"
  external get_last_conn_error : [>`R] Connect.t -> t option = "ocaml_libvirt_virterror_get_last_conn_error"
  external reset_last_error : unit -> unit = "ocaml_libvirt_virterror_reset_last_error"
  external reset_last_conn_error : [>`R] Connect.t -> unit = "ocaml_libvirt_virterror_reset_last_conn_error"

  let no_error () =
    { code = VIR_ERR_OK; domain = VIR_FROM_NONE;
      message = None; level = VIR_ERR_NONE;
      str1 = None; str2 = None; str3 = None;
      int1 = 0_l; int2 = 0_l }
end

exception Virterror of Virterror.t
exception Not_supported of string

let rec map_ignore_errors f = function
  | [] -> []
  | x :: xs ->
      try f x :: map_ignore_errors f xs
      with Virterror _ -> map_ignore_errors f xs

module Domain =
struct
  type 'rw t

  type state =
    | InfoNoState | InfoRunning | InfoBlocked | InfoPaused
    | InfoShutdown | InfoShutoff | InfoCrashed | InfoPMSuspended

  type info = {
    state : state;
    max_mem : int64;
    memory : int64;
    nr_virt_cpu : int;
    cpu_time : int64;
  }

  type vcpu_state = VcpuOffline | VcpuRunning | VcpuBlocked

  type vcpu_info = {
    number : int;
    vcpu_state : vcpu_state;
    vcpu_time : int64;
    cpu : int;
  }

  type domain_create_flag =
  | START_PAUSED
  | START_AUTODESTROY
  | START_BYPASS_CACHE
  | START_FORCE_BOOT
  | START_VALIDATE
  let rec int_of_domain_create_flags = function
    | [] -> 0
    | START_PAUSED :: flags ->       1 lor int_of_domain_create_flags flags
    | START_AUTODESTROY :: flags ->  2 lor int_of_domain_create_flags flags
    | START_BYPASS_CACHE :: flags -> 4 lor int_of_domain_create_flags flags
    | START_FORCE_BOOT :: flags ->   8 lor int_of_domain_create_flags flags
    | START_VALIDATE :: flags ->    16 lor int_of_domain_create_flags flags

  type sched_param = string * sched_param_value
  and sched_param_value =
    | SchedFieldInt32 of int32 | SchedFieldUInt32 of int32
    | SchedFieldInt64 of int64 | SchedFieldUInt64 of int64
    | SchedFieldFloat of float | SchedFieldBool of bool

  type typed_param = string * typed_param_value
  and typed_param_value =
    | TypedFieldInt32 of int32 | TypedFieldUInt32 of int32
    | TypedFieldInt64 of int64 | TypedFieldUInt64 of int64
    | TypedFieldFloat of float | TypedFieldBool of bool
    | TypedFieldString of string

  type migrate_flag = Live

  type memory_flag = Virtual

  type list_flag =
    | ListActive
    | ListInactive
    | ListAll

  type block_stats = {
    rd_req : int64;
    rd_bytes : int64;
    wr_req : int64;
    wr_bytes : int64;
    errs : int64;
  }

  type interface_stats = {
    rx_bytes : int64;
    rx_packets : int64;
    rx_errs : int64;
    rx_drop : int64;
    tx_bytes : int64;
    tx_packets : int64;
    tx_errs : int64;
    tx_drop : int64;
  }

  type get_all_domain_stats_flag =
    | GetAllDomainsStatsActive
    | GetAllDomainsStatsInactive
    | GetAllDomainsStatsOther
    | GetAllDomainsStatsPaused
    | GetAllDomainsStatsPersistent
    | GetAllDomainsStatsRunning
    | GetAllDomainsStatsShutoff
    | GetAllDomainsStatsTransient
    | GetAllDomainsStatsBacking
    | GetAllDomainsStatsEnforceStats

  type stats_type =
    | StatsState | StatsCpuTotal | StatsBalloon | StatsVcpu
    | StatsInterface | StatsBlock | StatsPerf

  type domain_stats_record = {
    dom_uuid : uuid;
    params : typed_param array;
  }

  type xml_desc_flag =
    | XmlSecure
    | XmlInactive
    | XmlUpdateCPU
    | XmlMigratable

  (* The maximum size for Domain.memory_peek and Domain.block_peek
   * supported by libvirt.  This may change with different versions
   * of libvirt in the future, hence it's a function.
   *)
  let max_peek _ = 65536

  external create_linux : [>`W] Connect.t -> xml -> rw t = "ocaml_libvirt_domain_create_linux"
  external _create_xml : [>`W] Connect.t -> xml -> int -> rw t = "ocaml_libvirt_domain_create_xml"
  let create_xml conn xml flags =
    _create_xml conn xml (int_of_domain_create_flags flags)
  external lookup_by_id : 'a Connect.t -> int -> 'a t = "ocaml_libvirt_domain_lookup_by_id"
  external lookup_by_uuid : 'a Connect.t -> uuid -> 'a t = "ocaml_libvirt_domain_lookup_by_uuid"
  external lookup_by_uuid_string : 'a Connect.t -> string -> 'a t = "ocaml_libvirt_domain_lookup_by_uuid_string"
  external lookup_by_name : 'a Connect.t -> string -> 'a t = "ocaml_libvirt_domain_lookup_by_name"
  external destroy : [>`W] t -> unit = "ocaml_libvirt_domain_destroy"
  external free : [>`R] t -> unit = "ocaml_libvirt_domain_free"
  external suspend : [>`W] t -> unit = "ocaml_libvirt_domain_suspend"
  external resume : [>`W] t -> unit = "ocaml_libvirt_domain_resume"
  external save : [>`W] t -> filename -> unit = "ocaml_libvirt_domain_save"
  external restore : [>`W] Connect.t -> filename -> unit = "ocaml_libvirt_domain_restore"
  external core_dump : [>`W] t -> filename -> unit = "ocaml_libvirt_domain_core_dump"
  external shutdown : [>`W] t -> unit = "ocaml_libvirt_domain_shutdown"
  external reboot : [>`W] t -> unit = "ocaml_libvirt_domain_reboot"
  external get_name : [>`R] t -> string = "ocaml_libvirt_domain_get_name"
  external get_uuid : [>`R] t -> uuid = "ocaml_libvirt_domain_get_uuid"
  external get_uuid_string : [>`R] t -> string = "ocaml_libvirt_domain_get_uuid_string"
  external get_id : [>`R] t -> int = "ocaml_libvirt_domain_get_id"
  external get_os_type : [>`R] t -> string = "ocaml_libvirt_domain_get_os_type"
  external get_max_memory : [>`R] t -> int64 = "ocaml_libvirt_domain_get_max_memory"
  external set_max_memory : [>`W] t -> int64 -> unit = "ocaml_libvirt_domain_set_max_memory"
  external set_memory : [>`W] t -> int64 -> unit = "ocaml_libvirt_domain_set_memory"
  external get_info : [>`R] t -> info = "ocaml_libvirt_domain_get_info"
  external get_xml_desc : [>`R] t -> xml = "ocaml_libvirt_domain_get_xml_desc"
  external get_xml_desc_flags : [>`W] t -> xml_desc_flag list -> xml = "ocaml_libvirt_domain_get_xml_desc_flags"
  external get_scheduler_type : [>`R] t -> string * int = "ocaml_libvirt_domain_get_scheduler_type"
  external get_scheduler_parameters : [>`R] t -> int -> sched_param array = "ocaml_libvirt_domain_get_scheduler_parameters"
  external set_scheduler_parameters : [>`W] t -> sched_param array -> unit = "ocaml_libvirt_domain_set_scheduler_parameters"
  external define_xml : [>`W] Connect.t -> xml -> rw t = "ocaml_libvirt_domain_define_xml"
  external undefine : [>`W] t -> unit = "ocaml_libvirt_domain_undefine"
  external create : [>`W] t -> unit = "ocaml_libvirt_domain_create"
  external get_autostart : [>`R] t -> bool = "ocaml_libvirt_domain_get_autostart"
  external set_autostart : [>`W] t -> bool -> unit = "ocaml_libvirt_domain_set_autostart"
  external set_vcpus : [>`W] t -> int -> unit = "ocaml_libvirt_domain_set_vcpus"
  external pin_vcpu : [>`W] t -> int -> string -> unit = "ocaml_libvirt_domain_pin_vcpu"
  external get_vcpus : [>`R] t -> int -> int -> int * vcpu_info array * string = "ocaml_libvirt_domain_get_vcpus"
  external get_cpu_stats : [>`R] t -> typed_param list array = "ocaml_libvirt_domain_get_cpu_stats"
  external get_max_vcpus : [>`R] t -> int = "ocaml_libvirt_domain_get_max_vcpus"
  external attach_device : [>`W] t -> xml -> unit = "ocaml_libvirt_domain_attach_device"
  external detach_device : [>`W] t -> xml -> unit = "ocaml_libvirt_domain_detach_device"
  external migrate : [>`W] t -> [>`W] Connect.t -> migrate_flag list -> ?dname:string -> ?uri:string -> ?bandwidth:int -> unit -> rw t = "ocaml_libvirt_domain_migrate_bytecode" "ocaml_libvirt_domain_migrate_native"
  external block_stats : [>`R] t -> string -> block_stats = "ocaml_libvirt_domain_block_stats"
  external interface_stats : [>`R] t -> string -> interface_stats = "ocaml_libvirt_domain_interface_stats"
  external block_peek : [>`W] t -> string -> int64 -> int -> string -> int -> unit = "ocaml_libvirt_domain_block_peek_bytecode" "ocaml_libvirt_domain_block_peek_native"
  external memory_peek : [>`W] t -> memory_flag list -> int64 -> int -> string -> int -> unit = "ocaml_libvirt_domain_memory_peek_bytecode" "ocaml_libvirt_domain_memory_peek_native"

  external get_all_domain_stats : [>`R] Connect.t -> stats_type list -> get_all_domain_stats_flag list -> domain_stats_record array = "ocaml_libvirt_domain_get_all_domain_stats"

  external const : [>`R] t -> ro t = "%identity"

  let get_domains conn flags =
    (* Old/slow/inefficient method. *)
    let get_active, get_inactive =
      if List.mem ListAll flags then
	(true, true)
      else
	(List.mem ListActive flags, List.mem ListInactive flags) in
    let active_doms =
      if get_active then (
	let n = Connect.num_of_domains conn in
	let ids = Connect.list_domains conn n in
	let ids = Array.to_list ids in
	map_ignore_errors (lookup_by_id conn) ids
      ) else [] in

    let inactive_doms =
      if get_inactive then (
	let n = Connect.num_of_defined_domains conn in
	let names = Connect.list_defined_domains conn n in
	let names = Array.to_list names in
	map_ignore_errors (lookup_by_name conn) names
      ) else [] in

    active_doms @ inactive_doms

  let get_domains_and_infos conn flags =
    (* Old/slow/inefficient method. *)
    let get_active, get_inactive =
      if List.mem ListAll flags then
	(true, true)
      else (List.mem ListActive flags, List.mem ListInactive flags) in
    let active_doms =
      if get_active then (
	let n = Connect.num_of_domains conn in
	let ids = Connect.list_domains conn n in
	let ids = Array.to_list ids in
	map_ignore_errors (lookup_by_id conn) ids
      ) else [] in

    let inactive_doms =
      if get_inactive then (
	let n = Connect.num_of_defined_domains conn in
	let names = Connect.list_defined_domains conn n in
	let names = Array.to_list names in
	map_ignore_errors (lookup_by_name conn) names
      ) else [] in

    let doms = active_doms @ inactive_doms in

    map_ignore_errors (fun dom -> (dom, get_info dom)) doms
end

module Event =
struct

  module Defined = struct
    type t = [
      | `Added
      | `Updated
      | `Unknown of int
    ]

    let to_string = function
      | `Added -> "Added"
      | `Updated -> "Updated"
      | `Unknown x -> Printf.sprintf "Unknown Defined.detail: %d" x

    let make = function
      | 0 -> `Added
      | 1 -> `Updated
      | x -> `Unknown x (* newer libvirt *)
  end

  module Undefined = struct
    type t = [
      | `Removed
      | `Unknown of int
    ]

    let to_string = function
      | `Removed -> "UndefinedRemoved"
      | `Unknown x -> Printf.sprintf "Unknown Undefined.detail: %d" x

    let make = function
      | 0 -> `Removed
      | x -> `Unknown x (* newer libvirt *)
  end

  module Started = struct
    type t = [
      | `Booted
      | `Migrated
      | `Restored
      | `FromSnapshot
      | `Wakeup
      | `Unknown of int
    ]

    let to_string = function
      | `Booted -> "Booted"
      | `Migrated -> "Migrated"
      | `Restored -> "Restored"
      | `FromSnapshot -> "FromSnapshot"
      | `Wakeup -> "Wakeup"
      | `Unknown x -> Printf.sprintf "Unknown Started.detail: %d" x
 
    let make = function
      | 0 -> `Booted
      | 1 -> `Migrated
      | 2 -> `Restored
      | 3 -> `FromSnapshot
      | 4 -> `Wakeup
      | x -> `Unknown x (* newer libvirt *)
  end

  module Suspended = struct
    type t = [
      | `Paused
      | `Migrated
      | `IOError
      | `Watchdog
      | `Restored
      | `FromSnapshot
      | `APIError
      | `Unknown of int (* newer libvirt *)
    ]

    let to_string = function
      | `Paused -> "Paused"
      | `Migrated -> "Migrated"
      | `IOError -> "IOError"
      | `Watchdog -> "Watchdog"
      | `Restored -> "Restored"
      | `FromSnapshot -> "FromSnapshot"
      | `APIError -> "APIError"
      | `Unknown x -> Printf.sprintf "Unknown Suspended.detail: %d" x

     let make = function
      | 0 -> `Paused
      | 1 -> `Migrated
      | 2 -> `IOError
      | 3 -> `Watchdog
      | 4 -> `Restored
      | 5 -> `FromSnapshot
      | 6 -> `APIError
      | x -> `Unknown x (* newer libvirt *)
  end

  module Resumed = struct
    type t = [
      | `Unpaused
      | `Migrated
      | `FromSnapshot
      | `Unknown of int (* newer libvirt *)
    ]

    let to_string = function
      | `Unpaused -> "Unpaused"
      | `Migrated -> "Migrated"
      | `FromSnapshot -> "FromSnapshot"
      | `Unknown x -> Printf.sprintf "Unknown Resumed.detail: %d" x

    let make = function
      | 0 -> `Unpaused
      | 1 -> `Migrated
      | 2 -> `FromSnapshot
      | x -> `Unknown x (* newer libvirt *)
  end

  module Stopped = struct
    type t = [
      | `Shutdown
      | `Destroyed
      | `Crashed
      | `Migrated
      | `Saved
      | `Failed
      | `FromSnapshot
      | `Unknown of int
    ]
    let to_string = function
      | `Shutdown -> "Shutdown"
      | `Destroyed -> "Destroyed"
      | `Crashed -> "Crashed"
      | `Migrated -> "Migrated"
      | `Saved -> "Saved"
      | `Failed -> "Failed"
      | `FromSnapshot -> "FromSnapshot"
      | `Unknown x -> Printf.sprintf "Unknown Stopped.detail: %d" x

    let make = function
      | 0 -> `Shutdown
      | 1 -> `Destroyed
      | 2 -> `Crashed
      | 3 -> `Migrated
      | 4 -> `Saved
      | 5 -> `Failed
      | 6 -> `FromSnapshot
      | x -> `Unknown x (* newer libvirt *)
  end

  module PM_suspended = struct
    type t = [
      | `Memory
      | `Disk
      | `Unknown of int (* newer libvirt *)
    ]

    let to_string = function
      | `Memory -> "Memory"
      | `Disk -> "Disk"
      | `Unknown x -> Printf.sprintf "Unknown PM_suspended.detail: %d" x

    let make = function
      | 0 -> `Memory
      | 1 -> `Disk
      | x -> `Unknown x (* newer libvirt *)
  end

  let string_option x = match x with
    | None -> "None"
    | Some x' -> "Some " ^ x'

  module Lifecycle = struct
    type t = [
      | `Defined of Defined.t
      | `Undefined of Undefined.t
      | `Started of Started.t
      | `Suspended of Suspended.t
      | `Resumed of Resumed.t
      | `Stopped of Stopped.t
      | `Shutdown (* no detail defined yet *)
      | `PMSuspended of PM_suspended.t
      | `Unknown of int (* newer libvirt *)
    ]

    let to_string = function
      | `Defined x -> "Defined " ^ (Defined.to_string x)
      | `Undefined x -> "Undefined " ^ (Undefined.to_string x)
      | `Started x -> "Started " ^ (Started.to_string x)
      | `Suspended x -> "Suspended " ^ (Suspended.to_string x)
      | `Resumed x -> "Resumed " ^ (Resumed.to_string x)
      | `Stopped x -> "Stopped " ^ (Stopped.to_string x)
      | `Shutdown -> "Shutdown"
      | `PMSuspended x -> "PMSuspended " ^ (PM_suspended.to_string x)
      | `Unknown x -> Printf.sprintf "Unknown Lifecycle event: %d" x

    let make (ty, detail) = match ty with
      | 0 -> `Defined (Defined.make detail)
      | 1 -> `Undefined (Undefined.make detail)
      | 2 -> `Started (Started.make detail)
      | 3 -> `Suspended (Suspended.make detail)
      | 4 -> `Resumed (Resumed.make detail)
      | 5 -> `Stopped (Stopped.make detail)
      | 6 -> `Shutdown
      | 7 -> `PMSuspended (PM_suspended.make detail)
      | x -> `Unknown x
  end

  module Reboot = struct
    type t = unit

    let to_string _ = "()"

    let make () = ()
  end

  module Rtc_change = struct
    type t = int64

    let to_string = Int64.to_string

    let make x = x
  end

  module Watchdog = struct
    type t = [
      | `None
      | `Pause
      | `Reset
      | `Poweroff
      | `Shutdown
      | `Debug
      | `Unknown of int
    ]

    let to_string = function
      | `None -> "None"
      | `Pause -> "Pause"
      | `Reset -> "Reset"
      | `Poweroff -> "Poweroff"
      | `Shutdown -> "Shutdown"
      | `Debug -> "Debug"
      | `Unknown x -> Printf.sprintf "Unknown watchdog_action: %d" x

    let make = function
      | 0 -> `None
      | 1 -> `Pause
      | 2 -> `Reset
      | 3 -> `Poweroff
      | 4 -> `Shutdown
      | 5 -> `Debug
      | x -> `Unknown x (* newer libvirt *)
  end

  module Io_error = struct
    type action = [
      | `None
      | `Pause
      | `Report
      | `Unknown of int (* newer libvirt *)
    ]

    let string_of_action = function
      | `None -> "None"
      | `Pause -> "Pause"
      | `Report -> "Report"
      | `Unknown x -> Printf.sprintf "Unknown Io_error.action: %d" x

    let action_of_int = function
      | 0 -> `None
      | 1 -> `Pause
      | 2 -> `Report
      | x -> `Unknown x

    type t = {
      src_path: string option;
      dev_alias: string option;
      action: action;
      reason: string option;
    }

    let to_string t = Printf.sprintf
        "{ Io_error.src_path = %s; dev_alias = %s; action = %s; reason = %s }"
        (string_option t.src_path)
        (string_option t.dev_alias)
        (string_of_action t.action)
        (string_option t.reason)

    let make (src_path, dev_alias, action, reason) = {
        src_path = src_path;
        dev_alias = dev_alias;
        action = action_of_int action;
        reason = reason;
    }

    let make_noreason (src_path, dev_alias, action) =
      make (src_path, dev_alias, action, None)
  end

  module Graphics_address = struct
    type family = [
      | `Ipv4
      | `Ipv6
      | `Unix
      | `Unknown of int (* newer libvirt *)
    ]

    let string_of_family = function
      | `Ipv4 -> "IPv4"
      | `Ipv6 -> "IPv6"
      | `Unix -> "UNIX"
      | `Unknown x -> Printf.sprintf "Unknown Graphics_address.family: %d" x

    let family_of_int = function
      (* no zero *)
      | 1 -> `Ipv4
      | 2 -> `Ipv6
      | 3 -> `Unix
      | x -> `Unknown x

    type t = {
      family: family;         (** Address family *)
      node: string option;    (** Address of node (eg IP address, or UNIX path *)
      service: string option; (** Service name/number (eg TCP port, or NULL) *)
    }

    let to_string t = Printf.sprintf
      "{ family = %s; node = %s; service = %s }"
        (string_of_family t.family)
        (string_option t.node)
        (string_option t.service)

    let make (family, node, service) = {
      family = family_of_int family;
      node = node;
      service = service;
    }
  end

  module Graphics_subject = struct
    type identity = {
      ty: string option;
      name: string option;
    }

    let string_of_identity t = Printf.sprintf
      "{ ty = %s; name = %s }"
      (string_option t.ty)
      (string_option t.name)

    type t = identity list

    let to_string ts =
      "[ " ^ (String.concat "; " (List.map string_of_identity ts)) ^ " ]"

    let make xs =
      List.map (fun (ty, name) -> { ty = ty; name = name })
        (Array.to_list xs)
  end

  module Graphics = struct
    type phase = [
      | `Connect
      | `Initialize
      | `Disconnect
      | `Unknown of int (** newer libvirt *)
    ]

    let string_of_phase = function
      | `Connect -> "Connect"
      | `Initialize -> "Initialize"
      | `Disconnect -> "Disconnect"
      | `Unknown x -> Printf.sprintf "Unknown Graphics.phase: %d" x

    let phase_of_int = function
      | 0 -> `Connect
      | 1 -> `Initialize
      | 2 -> `Disconnect
      | x -> `Unknown x

    type t = {
      phase: phase;                (** the phase of the connection *)
      local: Graphics_address.t;   (** the local server address *)
      remote: Graphics_address.t;  (** the remote client address *)
      auth_scheme: string option;  (** the authentication scheme activated *)
      subject: Graphics_subject.t; (** the authenticated subject (user) *)
    }

    let to_string t =
      let phase = Printf.sprintf "phase = %s"
        (string_of_phase t.phase) in
      let local = Printf.sprintf "local = %s"
        (Graphics_address.to_string t.local) in
      let remote = Printf.sprintf "remote = %s"
        (Graphics_address.to_string t.remote) in
      let auth_scheme = Printf.sprintf "auth_scheme = %s"
        (string_option t.auth_scheme) in
      let subject = Printf.sprintf "subject = %s"
        (Graphics_subject.to_string t.subject) in
      "{ " ^ (String.concat "; " [ phase; local; remote; auth_scheme; subject ]) ^ " }"

    let make (phase, local, remote, auth_scheme, subject) = {
      phase = phase_of_int phase;
      local = Graphics_address.make local;
      remote = Graphics_address.make remote;
      auth_scheme = auth_scheme;
      subject = Graphics_subject.make subject;
    }
  end

  module Control_error = struct
    type t = unit

    let to_string () = "()"

    let make () = ()
  end

  module Block_job = struct
    type ty = [
      | `KnownUnknown (* explicitly named UNKNOWN in the spec *)
      | `Pull
      | `Copy
      | `Commit
      | `Unknown of int (* newer libvirt *)
    ]

    let string_of_ty = function
      | `KnownUnknown -> "KnownUnknown"
      | `Pull -> "Pull"
      | `Copy -> "Copy"
      | `Commit -> "Commit"
      | `Unknown x -> Printf.sprintf "Unknown Block_job.ty: %d" x

    let ty_of_int = function
      | 0 -> `KnownUnknown
      | 1 -> `Pull
      | 2 -> `Copy
      | 3 -> `Commit
      | x -> `Unknown x (* newer libvirt *)

    type status = [
      | `Completed
      | `Failed
      | `Cancelled
      | `Ready
      | `Unknown of int
    ]

    let string_of_status = function
      | `Completed -> "Completed"
      | `Failed -> "Failed"
      | `Cancelled -> "Cancelled"
      | `Ready -> "Ready"
      | `Unknown x -> Printf.sprintf "Unknown Block_job.status: %d" x

    let status_of_int = function
      | 0 -> `Completed
      | 1 -> `Failed
      | 2 -> `Cancelled
      | 3 -> `Ready
      | x -> `Unknown x

    type t = {
      disk: string option;
      ty: ty;
      status: status;
    }

    let to_string t = Printf.sprintf "{ disk = %s; ty = %s; status = %s }"
      (string_option t.disk)
      (string_of_ty t.ty)
      (string_of_status t.status)

    let make (disk, ty, status) = {
      disk = disk;
      ty = ty_of_int ty;
      status = status_of_int ty;
    }
  end

  module Disk_change = struct
    type reason = [
      | `MissingOnStart
      | `Unknown of int
    ]

    let string_of_reason = function
      | `MissingOnStart -> "MissingOnStart"
      | `Unknown x -> Printf.sprintf "Unknown Disk_change.reason: %d" x

    let reason_of_int = function
      | 0 -> `MissingOnStart
      | x -> `Unknown x

    type t = {
      old_src_path: string option;
      new_src_path: string option;
      dev_alias: string option;
      reason: reason;
    }

    let to_string t =
      let o = Printf.sprintf "old_src_path = %s" (string_option t.old_src_path) in
      let n = Printf.sprintf "new_src_path = %s" (string_option t.new_src_path) in
      let d = Printf.sprintf "dev_alias = %s" (string_option t.dev_alias) in
      let r = string_of_reason t.reason in
      "{ " ^ (String.concat "; " [ o; n; d; r ]) ^ " }"

    let make (o, n, d, r) = {
      old_src_path = o;
      new_src_path = n;
      dev_alias = d;
      reason = reason_of_int r;
    }
  end

  module Tray_change = struct
    type reason = [
      | `Open
      | `Close
      | `Unknown of int
    ]

    let string_of_reason = function
      | `Open -> "Open"
      | `Close -> "Close"
      | `Unknown x -> Printf.sprintf "Unknown Tray_change.reason: %d" x

    let reason_of_int = function
      | 0 -> `Open
      | 1 -> `Close
      | x -> `Unknown x

    type t = {
      dev_alias: string option;
      reason: reason;
    }

    let to_string t = Printf.sprintf
      "{ dev_alias = %s; reason = %s }"
        (string_option t.dev_alias)
        (string_of_reason t.reason)

    let make (dev_alias, reason) = {
      dev_alias = dev_alias;
      reason = reason_of_int reason;
    }
  end

  module PM_wakeup = struct
    type reason = [
      | `Unknown of int
    ]

    type t = reason

    let to_string = function
      | `Unknown x -> Printf.sprintf "Unknown PM_wakeup.reason: %d" x

    let make x = `Unknown x
  end

  module PM_suspend = struct
    type reason = [
      | `Unknown of int
    ]

    type t = reason

    let to_string = function
      | `Unknown x -> Printf.sprintf "Unknown PM_suspend.reason: %d" x

    let make x = `Unknown x
  end

  module Balloon_change = struct
    type t = int64

    let to_string = Int64.to_string
    let make x = x
  end

  module PM_suspend_disk = struct
    type reason = [
      | `Unknown of int
    ]

    type t = reason

    let to_string = function
      | `Unknown x -> Printf.sprintf "Unknown PM_suspend_disk.reason: %d" x

    let make x = `Unknown x
  end

  type callback =
    | Lifecycle     of ([`R] Domain.t -> Lifecycle.t -> unit)
    | Reboot        of ([`R] Domain.t -> Reboot.t -> unit)
    | RtcChange     of ([`R] Domain.t -> Rtc_change.t -> unit)
    | Watchdog      of ([`R] Domain.t -> Watchdog.t -> unit)
    | IOError       of ([`R] Domain.t -> Io_error.t -> unit)
    | Graphics      of ([`R] Domain.t -> Graphics.t -> unit)
    | IOErrorReason of ([`R] Domain.t -> Io_error.t -> unit)
    | ControlError  of ([`R] Domain.t -> Control_error.t -> unit)
    | BlockJob      of ([`R] Domain.t -> Block_job.t -> unit)
    | DiskChange    of ([`R] Domain.t -> Disk_change.t -> unit)
    | TrayChange    of ([`R] Domain.t -> Tray_change.t -> unit)
    | PMWakeUp      of ([`R] Domain.t -> PM_wakeup.t -> unit)
    | PMSuspend     of ([`R] Domain.t -> PM_suspend.t -> unit)
    | BalloonChange of ([`R] Domain.t -> Balloon_change.t -> unit)
    | PMSuspendDisk of ([`R] Domain.t -> PM_suspend_disk.t -> unit)

  type callback_id = int64

  let fresh_callback_id =
    let next = ref 0L in
    fun () ->
      let result = !next in
      next := Int64.succ !next;
      result

  let make_table value_name =
    let table = Hashtbl.create 16 in
    let callback callback_id generic x =
      if Hashtbl.mem table callback_id
      then Hashtbl.find table callback_id generic x in
    let _ = Callback.register value_name callback in
    table

  let u_table = make_table "Libvirt.u_callback"
  let i_table = make_table "Libvirt.i_callback"
  let i64_table = make_table "Libvirt.i64_callback"
  let i_i_table = make_table "Libvirt.i_i_callback"
  let s_i_table = make_table "Libvirt.s_i_callback"
  let s_i_i_table = make_table "Libvirt.s_i_i_callback"
  let s_s_i_table = make_table "Libvirt.s_s_i_callback"
  let s_s_i_s_table = make_table "Libvirt.s_s_i_s_callback"
  let s_s_s_i_table = make_table "Libvirt.s_s_s_i_callback"
  let i_ga_ga_s_gs_table = make_table "Libvirt.i_ga_ga_s_gs_callback"

  external register_default_impl : unit -> unit = "ocaml_libvirt_event_register_default_impl"

  external run_default_impl : unit -> unit = "ocaml_libvirt_event_run_default_impl"

  external register_any' : 'a Connect.t -> 'a Domain.t option -> callback -> callback_id -> int = "ocaml_libvirt_connect_domain_event_register_any"

  external deregister_any' : 'a Connect.t -> int -> unit = "ocaml_libvirt_connect_domain_event_deregister_any"

  let our_id_to_libvirt_id = Hashtbl.create 16

  let register_any conn ?dom callback =
    let id = fresh_callback_id () in
    begin match callback with
    | Lifecycle f ->
        Hashtbl.add i_i_table id (fun dom x ->
            f dom (Lifecycle.make x)
        )
    | Reboot f ->
        Hashtbl.add u_table id (fun dom x ->
            f dom (Reboot.make x)
        )
    | RtcChange f ->
        Hashtbl.add i64_table id (fun dom x ->
            f dom (Rtc_change.make x)
        )
    | Watchdog f ->
        Hashtbl.add i_table id (fun dom x ->
            f dom (Watchdog.make x)
        ) 
    | IOError f ->
        Hashtbl.add s_s_i_table id (fun dom x ->
            f dom (Io_error.make_noreason x)
        )
    | Graphics f ->
        Hashtbl.add i_ga_ga_s_gs_table id (fun dom x ->
            f dom (Graphics.make x)
        )
    | IOErrorReason f ->
        Hashtbl.add s_s_i_s_table id (fun dom x ->
            f dom (Io_error.make x)
        )
    | ControlError f ->
        Hashtbl.add u_table id (fun dom x ->
            f dom (Control_error.make x)
        )
    | BlockJob f ->
        Hashtbl.add s_i_i_table id (fun dom x ->
            f dom (Block_job.make x)
        )
    | DiskChange f ->
        Hashtbl.add s_s_s_i_table id (fun dom x ->
            f dom (Disk_change.make x)
        )
    | TrayChange f ->
        Hashtbl.add s_i_table id (fun dom x ->
            f dom (Tray_change.make x)
        )
    | PMWakeUp f ->
        Hashtbl.add i_table id (fun dom x ->
            f dom (PM_wakeup.make x)
        )
    | PMSuspend f ->
        Hashtbl.add i_table id (fun dom x ->
            f dom (PM_suspend.make x)
        )
    | BalloonChange f ->
        Hashtbl.add i64_table id (fun dom x ->
            f dom (Balloon_change.make x)
        )
    | PMSuspendDisk f ->
        Hashtbl.add i_table id (fun dom x ->
            f dom (PM_suspend_disk.make x)
        )
    end;
    let libvirt_id = register_any' conn dom callback id in
    Hashtbl.replace our_id_to_libvirt_id id libvirt_id;
    id

  let deregister_any conn id =
    if Hashtbl.mem our_id_to_libvirt_id id then begin
      let libvirt_id = Hashtbl.find our_id_to_libvirt_id id in
      deregister_any' conn libvirt_id
    end;
    Hashtbl.remove our_id_to_libvirt_id id;
    Hashtbl.remove u_table id;
    Hashtbl.remove i_table id;
    Hashtbl.remove i64_table id;
    Hashtbl.remove i_i_table id;
    Hashtbl.remove s_i_table id;
    Hashtbl.remove s_i_i_table id;
    Hashtbl.remove s_s_i_table id;
    Hashtbl.remove s_s_i_s_table id;
    Hashtbl.remove s_s_s_i_table id;
    Hashtbl.remove i_ga_ga_s_gs_table id

  let timeout_table = Hashtbl.create 16
  let _ =
    let callback x =
      if Hashtbl.mem timeout_table x
      then Hashtbl.find timeout_table x () in
  Callback.register "Libvirt.timeout_callback" callback

  type timer_id = int64

  external add_timeout' : 'a Connect.t -> int -> int64 -> int = "ocaml_libvirt_event_add_timeout"

  external remove_timeout' : 'a Connect.t -> int -> unit = "ocaml_libvirt_event_remove_timeout"

  let our_id_to_timer_id = Hashtbl.create 16
  let add_timeout conn ms fn =
    let id = fresh_callback_id () in
    Hashtbl.add timeout_table id fn;
    let timer_id = add_timeout' conn ms id in
    Hashtbl.add our_id_to_timer_id id timer_id;
    id

  let remove_timeout conn id =
    if Hashtbl.mem our_id_to_timer_id id then begin
      let timer_id = Hashtbl.find our_id_to_timer_id id in
      remove_timeout' conn timer_id
    end;
    Hashtbl.remove our_id_to_timer_id id;
    Hashtbl.remove timeout_table id
end

module Network =
struct
  type 'rw t

  external lookup_by_name : 'a Connect.t -> string -> 'a t = "ocaml_libvirt_network_lookup_by_name"
  external lookup_by_uuid : 'a Connect.t -> uuid -> 'a t = "ocaml_libvirt_network_lookup_by_uuid"
  external lookup_by_uuid_string : 'a Connect.t -> string -> 'a t = "ocaml_libvirt_network_lookup_by_uuid_string"
  external create_xml : [>`W] Connect.t -> xml -> rw t = "ocaml_libvirt_network_create_xml"
  external define_xml : [>`W] Connect.t -> xml -> rw t = "ocaml_libvirt_network_define_xml"
  external undefine : [>`W] t -> unit = "ocaml_libvirt_network_undefine"
  external create : [>`W] t -> unit = "ocaml_libvirt_network_create"
  external destroy : [>`W] t -> unit = "ocaml_libvirt_network_destroy"
  external free : [>`R] t -> unit = "ocaml_libvirt_network_free"
  external get_name : [>`R] t -> string = "ocaml_libvirt_network_get_name"
  external get_uuid : [>`R] t -> uuid = "ocaml_libvirt_network_get_uuid"
  external get_uuid_string : [>`R] t -> string = "ocaml_libvirt_network_get_uuid_string"
  external get_xml_desc : [>`R] t -> xml = "ocaml_libvirt_network_get_xml_desc"
  external get_bridge_name : [>`R] t -> string = "ocaml_libvirt_network_get_bridge_name"
  external get_autostart : [>`R] t -> bool = "ocaml_libvirt_network_get_autostart"
  external set_autostart : [>`W] t -> bool -> unit = "ocaml_libvirt_network_set_autostart"

  external const : [>`R] t -> ro t = "%identity"
end

module Pool =
struct
  type 'rw t
  type pool_state = Inactive | Building | Running | Degraded | Inaccessible
  type pool_build_flags = New | Repair | Resize
  type pool_delete_flags = Normal | Zeroed
  type pool_info = {
    state : pool_state;
    capacity : int64;
    allocation : int64;
    available : int64;
  }

  external lookup_by_name : 'a Connect.t -> string -> 'a t = "ocaml_libvirt_storage_pool_lookup_by_name"
  external lookup_by_uuid : 'a Connect.t -> uuid -> 'a t = "ocaml_libvirt_storage_pool_lookup_by_uuid"
  external lookup_by_uuid_string : 'a Connect.t -> string -> 'a t = "ocaml_libvirt_storage_pool_lookup_by_uuid_string"
  external create_xml : [>`W] Connect.t -> xml -> rw t = "ocaml_libvirt_storage_pool_create_xml"
  external define_xml : [>`W] Connect.t -> xml -> rw t = "ocaml_libvirt_storage_pool_define_xml"
  external build : [>`W] t -> pool_build_flags -> unit = "ocaml_libvirt_storage_pool_build"
  external undefine : [>`W] t -> unit = "ocaml_libvirt_storage_pool_undefine"
  external create : [>`W] t -> unit = "ocaml_libvirt_storage_pool_create"
  external destroy : [>`W] t -> unit = "ocaml_libvirt_storage_pool_destroy"
  external delete : [>`W] t -> unit = "ocaml_libvirt_storage_pool_delete"
  external free : [>`R] t -> unit = "ocaml_libvirt_storage_pool_free"
  external refresh : [`R] t -> unit = "ocaml_libvirt_storage_pool_refresh"
  external get_name : [`R] t -> string = "ocaml_libvirt_storage_pool_get_name"
  external get_uuid : [`R] t -> uuid = "ocaml_libvirt_storage_pool_get_uuid"
  external get_uuid_string : [`R] t -> string = "ocaml_libvirt_storage_pool_get_uuid_string"
  external get_info : [`R] t -> pool_info = "ocaml_libvirt_storage_pool_get_info"
  external get_xml_desc : [`R] t -> xml = "ocaml_libvirt_storage_pool_get_xml_desc"
  external get_autostart : [`R] t -> bool = "ocaml_libvirt_storage_pool_get_autostart"
  external set_autostart : [>`W] t -> bool -> unit = "ocaml_libvirt_storage_pool_set_autostart"
  external num_of_volumes : [`R] t -> int = "ocaml_libvirt_storage_pool_num_of_volumes"
  external list_volumes : [`R] t -> int -> string array = "ocaml_libvirt_storage_pool_list_volumes"
  external const : [>`R] t -> ro t = "%identity"
end

module Volume =
struct
  type 'rw t
  type vol_type = File | Block | Dir | Network | NetDir | Ploop
  type vol_delete_flags = Normal | Zeroed
  type vol_info = {
    typ : vol_type;
    capacity : int64;
    allocation : int64;
  }

  external lookup_by_name : 'a Pool.t -> string -> 'a t = "ocaml_libvirt_storage_vol_lookup_by_name"
  external lookup_by_key : 'a Connect.t -> string -> 'a t = "ocaml_libvirt_storage_vol_lookup_by_key"
  external lookup_by_path : 'a Connect.t -> string -> 'a t = "ocaml_libvirt_storage_vol_lookup_by_path"
  external pool_of_volume : 'a t -> 'a Pool.t = "ocaml_libvirt_storage_pool_lookup_by_volume"
  external get_name : [`R] t -> string = "ocaml_libvirt_storage_vol_get_name"
  external get_key : [`R] t -> string = "ocaml_libvirt_storage_vol_get_key"
  external get_path : [`R] t -> string = "ocaml_libvirt_storage_vol_get_path"
  external get_info : [`R] t -> vol_info = "ocaml_libvirt_storage_vol_get_info"
  external get_xml_desc : [`R] t -> xml = "ocaml_libvirt_storage_vol_get_xml_desc"
  external create_xml : [>`W] Pool.t -> xml -> unit = "ocaml_libvirt_storage_vol_create_xml"
  external delete : [>`W] t -> vol_delete_flags -> unit = "ocaml_libvirt_storage_vol_delete"
  external free : [>`R] t -> unit = "ocaml_libvirt_storage_vol_free"
  external const : [>`R] t -> ro t = "%identity"
end

module Secret =
struct
  type 'rw t
  type secret_usage_type =
    | NoType
    | Volume
    | Ceph
    | ISCSI
    | TLS

  external lookup_by_uuid : 'a Connect.t -> uuid -> 'a t = "ocaml_libvirt_secret_lookup_by_uuid"
  external lookup_by_uuid_string : 'a Connect.t -> string -> 'a t = "ocaml_libvirt_secret_lookup_by_uuid_string"
  external lookup_by_usage : 'a Connect.t -> secret_usage_type -> string -> 'a t = "ocaml_libvirt_secret_lookup_by_usage"
  external define_xml : [>`W] Connect.t -> xml -> rw t = "ocaml_libvirt_secret_define_xml"
  external get_uuid : [>`R] t -> uuid = "ocaml_libvirt_secret_get_uuid"
  external get_uuid_string : [>`R] t -> string = "ocaml_libvirt_secret_get_uuid_string"
  external get_usage_type : [>`R] t -> secret_usage_type = "ocaml_libvirt_secret_get_usage_type"
  external get_usage_id : [>`R] t -> string = "ocaml_libvirt_secret_get_usage_id"
  external get_xml_desc : [>`R] t -> xml = "ocaml_libvirt_secret_get_xml_desc"
  external set_value : [>`W] t -> bytes -> unit = "ocaml_libvirt_secret_set_value"
  external get_value : [>`R] t -> bytes = "ocaml_libvirt_secret_get_value"
  external undefine : [>`W] t -> unit = "ocaml_libvirt_secret_undefine"
  external free : [>`R] t -> unit = "ocaml_libvirt_secret_free"
  external const : [>`R] t -> ro t = "%identity"
end

(* Initialization. *)
external c_init : unit -> unit = "ocaml_libvirt_init"
let () =
  Callback.register_exception
    "ocaml_libvirt_virterror" (Virterror (Virterror.no_error ()));
  Callback.register_exception
    "ocaml_libvirt_not_supported" (Not_supported "");
  c_init ();
  Printexc.register_printer (
    function
    | Virterror e -> Some (Virterror.to_string e)
    | _ -> None
  )
