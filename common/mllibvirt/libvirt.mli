(** OCaml bindings for libvirt. *)
(* (C) Copyright 2007-2015 Richard W.M. Jones, Red Hat Inc.
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

(**
   {2 Introduction and examples}

   This is a set of bindings for writing OCaml programs to
   manage virtual machines through {{:https://libvirt.org/}libvirt}.

   {3 Using libvirt interactively}

   Using the interactive toplevel:

{v
$ ocaml -I +libvirt
        Objective Caml version 3.10.0

# #load "unix.cma";;
# #load "mllibvirt.cma";;
# let name = "test:///default";;
val name : string = "test:///default"
# let conn = Libvirt.Connect.connect_readonly ~name () ;;
val conn : Libvirt.ro Libvirt.Connect.t = <abstr>
# Libvirt.Connect.get_node_info conn;;
  : Libvirt.Connect.node_info =
{Libvirt.Connect.model = "i686"; Libvirt.Connect.memory = 3145728L;
 Libvirt.Connect.cpus = 16; Libvirt.Connect.mhz = 1400;
 Libvirt.Connect.nodes = 2; Libvirt.Connect.sockets = 2;
 Libvirt.Connect.cores = 2; Libvirt.Connect.threads = 2}
v}

   {3 Compiling libvirt programs}

   This command compiles a program to native code:

{v
ocamlopt -I +libvirt mllibvirt.cmxa list_domains.ml -o list_domains
v}

   {3 Example: Connect to the hypervisor}

   The main modules are {!Libvirt.Connect}, {!Libvirt.Domain} and
   {!Libvirt.Network} corresponding respectively to the
   {{:https://libvirt.org/html/libvirt-libvirt-host.html}virConnect*},
   {{:https://libvirt.org/html/libvirt-libvirt-domain.html}virDomain*}, and
   {{:https://libvirt.org/html/libvirt-libvirt-network.html}virNetwork*}
   functions from libvirt.
   For brevity I usually rename these modules like this:

{[
module C = Libvirt.Connect
module D = Libvirt.Domain
module N = Libvirt.Network
]}

   To get a connection handle, assuming a Xen hypervisor:

{[
let name = "xen:///"
let conn = C.connect_readonly ~name ()
]}

   {3 Example: List running domains}

{[
open Printf

let domains = D.get_domains conn [D.ListActive] in
List.iter (
  fun dom ->
    printf "%8d %s\n%!" (D.get_id dom) (D.get_name dom)
) domains;
]}

   {3 Example: List inactive domains}

{[
let domains = D.get_domains conn [D.ListInactive] in
List.iter (
  fun dom ->
    printf "inactive %s\n%!" (D.get_name dom)
) domains;
]}

   {3 Example: Print node info}

{[
let node_info = C.get_node_info conn in
printf "model = %s\n" node_info.C.model;
printf "memory = %Ld K\n" node_info.C.memory;
printf "cpus = %d\n" node_info.C.cpus;
printf "mhz = %d\n" node_info.C.mhz;
printf "nodes = %d\n" node_info.C.nodes;
printf "sockets = %d\n" node_info.C.sockets;
printf "cores = %d\n" node_info.C.cores;
printf "threads = %d\n%!" node_info.C.threads;

let hostname = C.get_hostname conn in
printf "hostname = %s\n%!" hostname;

let uri = C.get_uri conn in
printf "uri = %s\n%!" uri
]}

*)


(** {2 Programming issues}

    {3 General safety issues}

    Memory allocation / automatic garbage collection of all libvirt
    objects should be completely safe.  If you find any safety issues
    or if your pure OCaml program ever segfaults, please contact the author.

    You can force a libvirt object to be freed early by calling
    the {!Libvirt.Connect.close} function on the object.  This shouldn't
    affect the safety of garbage collection and should only be used when
    you want to explicitly free memory.  Note that explicitly
    closing a connection object does nothing if there are still
    unclosed domain or network objects referencing it.

    Note that even though you hold open (eg) a domain object, that
    doesn't mean that the domain (virtual machine) actually exists.
    The domain could have been shut down or deleted by another user.
    Thus domain objects can raise odd exceptions at any time.
    This is just the nature of virtualisation.

    {3 Backwards and forwards compatibility}

    OCaml-libvirt requires libvirt version 1.2.8 or later. Future
    releases of OCaml-libvirt will use newer features of libvirt
    and therefore will require later versions of libvirt. It is always
    possible to dynamically link your application against a newer
    libvirt than OCaml-libvirt was originally compiled against.

    {3 Get list of domains and domain infos}

    This is a very common operation, and libvirt supports various
    different methods to do it.  We have hidden the complexity in a
    flexible {!Libvirt.Domain.get_domains} and
    {!Libvirt.Domain.get_domains_and_infos} calls which is easy to use and
    automatically chooses the most efficient method depending on the
    version of libvirt in use.

    {3 Threads}

    You can issue multiple concurrent libvirt requests in
    different threads.  However you must follow this rule:
    Each thread must have its own separate libvirt connection, {i or}
    you must implement your own mutex scheme to ensure that no
    two threads can ever make concurrent calls using the same
    libvirt connection.

    (Note that multithreaded code is not well tested.  If you find
    bugs please report them.)

    {3 Initialisation}

    Libvirt requires all callers to call virInitialize before
    using the library.  This is done automatically for you by
    these bindings when the program starts up, and we believe
    that the way this is done is safe.

    {2 Reference}
*)

type uuid = string
    (** This is a "raw" UUID, ie. a packed string of bytes. *)

type xml = string
    (** Type of XML (an uninterpreted string of bytes).  Use PXP, expat,
	xml-light, etc. if you want to do anything useful with the XML.
    *)

type filename = string
    (** A filename. *)

val get_version : ?driver:string -> unit -> int * int
  (** [get_version ()] returns the library version in the first part
      of the tuple, and [0] in the second part.

      [get_version ~driver ()] returns the library version in the first
      part of the tuple, and the version of the driver called [driver]
      in the second part.

      The version numbers are encoded as
      [major * 1_000_000 + minor * 1000 + release].
  *)

val uuid_length : int
  (** Length of packed UUIDs. *)

val uuid_string_length : int
  (** Length of UUID strings. *)

type rw = [`R|`W]
type ro = [`R]
    (** These
	{{:https://caml.inria.fr/pub/ml-archives/caml-list/2004/07/80683af867cce6bf8fff273973f70c95.en.html}phantom types}
	are used to ensure the type-safety of read-only
	versus read-write connections.

	All connection/domain/etc. objects are marked with
	a phantom read-write or read-only type, and trying to
	pass a read-only object into a function which could
	mutate the object will cause a compile time error.

	Each module provides a function like {!Libvirt.Connect.const}
	to demote a read-write object into a read-only object.  The
	opposite operation is, of course, not allowed.

	If you want to handle both read-write and read-only
	connections at runtime, use a variant similar to this:
{[
type conn_t =
    | No_connection
    | Read_only of Libvirt.ro Libvirt.Connect.t
    | Read_write of Libvirt.rw Libvirt.Connect.t
]}
    *)

(** {3 Forward definitions}

    These definitions are placed here to avoid the need to
    use recursive module dependencies.
*)

(** {3 Connections} *)

module Connect :
sig
  type 'rw t
    (** Connection.  Read-only connections have type [ro Connect.t] and
	read-write connections have type [rw Connect.t].
      *)

  type node_info = {
    model : string;			(** CPU model *)
    memory : int64;			(** memory size in kilobytes *)
    cpus : int;				(** number of active CPUs *)
    mhz : int;				(** expected CPU frequency *)
    nodes : int;			(** number of NUMA nodes (1 = UMA) *)
    sockets : int;			(** number of CPU sockets per node *)
    cores : int;			(** number of cores per socket *)
    threads : int;			(** number of threads per core *)
  }

  type credential_type =
    | CredentialUsername		(** Identity to act as *)
    | CredentialAuthname		(** Identify to authorize as *)
    | CredentialLanguage		(** RFC 1766 languages, comma separated *)
    | CredentialCnonce			(** client supplies a nonce *)
    | CredentialPassphrase		(** Passphrase secret *)
    | CredentialEchoprompt		(** Challenge response *)
    | CredentialNoechoprompt		(** Challenge response *)
    | CredentialRealm			(** Authentication realm *)
    | CredentialExternal		(** Externally managed credential *)

  type credential = {
    typ : credential_type;		(** The type of credential *)
    prompt : string;			(** Prompt to show to user *)
    challenge : string option;		(** Additional challenge to show *)
    defresult : string option;		(** Optional default result *)
  }

  type auth = {
    credtype : credential_type list;	(** List of supported credential_type values *)
    cb : (credential list -> string option list);
    (** Callback used to collect credentials.

	The input is a list of all the requested credentials.

	The function returns a list of all the results from the
	requested credentials, so the number of results {e must} match
	the number of input credentials.  Each result is optional,
	and in case it is [None] it means there was no result.
     *)
  }

  val connect : ?name:string -> unit -> rw t
    (** [connect ~name ()] connects to the hypervisor with URI [name].

	[connect ()] connects to the default hypervisor.
    *)
  val connect_readonly : ?name:string -> unit -> ro t
    (** [connect_readonly ~name ()] connects in read-only mode
	to the hypervisor with URI [name].

	[connect_readonly ()] connects in read-only mode to the
	default hypervisor.
    *)

  val connect_auth : ?name:string -> auth -> rw t
    (** [connect_auth ~name auth] connects to the hypervisor with URI
	[name], using [auth] as authentication handler.

	[connect_auth auth] connects to the default hypervisor, using
	[auth] as authentication handler.
    *)
  val connect_auth_readonly : ?name:string -> auth -> ro t
    (** [connect_auth_readonly ~name auth] connects in read-only mode
	to the hypervisor with URI [name], using [auth] as authentication
	handler.

	[connect_auth_readonly auth] connects in read-only mode to the
	default hypervisor, using [auth] as authentication handler.
    *)

  val close : [>`R] t -> unit
    (** [close conn] closes and frees the connection object in memory.

	The connection is automatically closed if it is garbage
	collected.  This function just forces it to be closed
	and freed right away.
    *)

  val get_type : [>`R] t -> string
    (** Returns the name of the driver (hypervisor). *)

  val get_version : [>`R] t -> int
    (** Returns the driver version
	[major * 1_000_000 + minor * 1000 + release]
    *)
  val get_hostname : [>`R] t -> string
    (** Returns the hostname of the physical server. *)
  val get_uri : [>`R] t -> string
    (** Returns the canonical connection URI. *)
  val get_max_vcpus : [>`R] t -> ?type_:string -> unit -> int
    (** Returns the maximum number of virtual CPUs
	supported by a guest VM of a particular type. *)
  val list_domains : [>`R] t -> int -> int array
    (** [list_domains conn max] returns the running domain IDs,
	up to a maximum of [max] entries.

	Call {!num_of_domains} first to get a value for [max].

	See also:
	{!Libvirt.Domain.get_domains},
	{!Libvirt.Domain.get_domains_and_infos}.
    *)
  val num_of_domains : [>`R] t -> int
    (** Returns the number of running domains. *)
  val get_capabilities : [>`R] t -> xml
    (** Returns the hypervisor capabilities (as XML). *)
  val num_of_defined_domains : [>`R] t -> int
    (** Returns the number of inactive (shutdown) domains. *)
  val list_defined_domains : [>`R] t -> int -> string array
    (** [list_defined_domains conn max]
	returns the names of the inactive domains, up to
	a maximum of [max] entries.

	Call {!num_of_defined_domains} first to get a value for [max].

	See also:
	{!Libvirt.Domain.get_domains},
	{!Libvirt.Domain.get_domains_and_infos}.
    *)
  val num_of_networks : [>`R] t -> int
    (** Returns the number of networks. *)
  val list_networks : [>`R] t -> int -> string array
    (** [list_networks conn max]
	returns the names of the networks, up to a maximum
	of [max] entries.
	Call {!num_of_networks} first to get a value for [max].
    *)
  val num_of_defined_networks : [>`R] t -> int
    (** Returns the number of inactive networks. *)
  val list_defined_networks : [>`R] t -> int -> string array
    (** [list_defined_networks conn max]
	returns the names of the inactive networks, up to a maximum
	of [max] entries.
	Call {!num_of_defined_networks} first to get a value for [max].
    *)

  val num_of_pools : [>`R] t -> int
    (** Returns the number of storage pools. *)
  val list_pools : [>`R] t -> int -> string array
    (** Return list of storage pools. *)
  val num_of_defined_pools : [>`R] t -> int
    (** Returns the number of storage pools. *)
  val list_defined_pools : [>`R] t -> int -> string array
    (** Return list of storage pools. *)

    (* The name of this function is inconsistent, but the inconsistency
     * is really in libvirt itself.
     *)
  val num_of_secrets : [>`R] t -> int
    (** Returns the number of secrets. *)
  val list_secrets : [>`R] t -> int -> string array
    (** Returns the list of secrets. *)
  val get_node_info : [>`R] t -> node_info
    (** Return information about the physical server. *)

  val node_get_free_memory : [> `R] t -> int64
    (**
       [node_get_free_memory conn]
       returns the amount of free memory (not allocated to any guest)
       in the machine.
    *)

  val node_get_cells_free_memory : [> `R] t -> int -> int -> int64 array
    (**
       [node_get_cells_free_memory conn start max]
       returns the amount of free memory on each NUMA cell in kilobytes.
       [start] is the first cell for which we return free memory.
       [max] is the maximum number of cells for which we return free memory.
       Returns an array of up to [max] entries in length.
    *)

  val maxcpus_of_node_info : node_info -> int
    (** Calculate the total number of CPUs supported (but not necessarily
	active) in the host.
    *)

  val cpumaplen : int -> int
    (** Calculate the length (in bytes) required to store the complete
	CPU map between a single virtual and all physical CPUs of a domain.
    *)

  val use_cpu : bytes -> int -> unit
    (** [use_cpu cpumap cpu] marks [cpu] as usable in [cpumap]. *)
  val unuse_cpu : bytes -> int -> unit
    (** [unuse_cpu cpumap cpu] marks [cpu] as not usable in [cpumap]. *)
  val cpu_usable : bytes -> int -> int -> int -> bool
    (** [cpu_usable cpumaps maplen vcpu cpu] checks returns true iff the
	[cpu] is usable by [vcpu]. *)

  val set_keep_alive : [>`R] t -> int -> int -> unit
    (** [set_keep_alive conn interval count] starts sending keepalive
        messages after [interval] seconds of inactivity and consider the
        connection to be broken when no response is received after [count]
        keepalive messages.
        Note: the client has to implement and run an event loop to
        be able to use keep-alive messages. *)

  val get_auth_default : unit -> auth
    (** [get_auth_default ()] returns the default authentication handler
	of libvirt.
      *)

  val get_domain_capabilities : ?emulatorbin:string -> ?arch:string -> ?machine:string -> ?virttype:string -> [>`R] t -> string
    (** [get_domain_capabilities ()] returns the XML with the
	available capabilities of the emulator or libvirt for domains.

	The optional flag [?emulatorbin] is used to specify a different
	emulator.

	The optional flag [?arch] is used to specify a different
	architecture.

	The optional flag [?machine] is used to specify a different
	machine type.

	The optional flag [?virttype] is used to specify a different
	type of virtualization. *)

  external const : [>`R] t -> ro t = "%identity"
    (** [const conn] turns a read/write connection into a read-only
	connection.  Note that the opposite operation is impossible.
      *)
end
  (** Module dealing with connections.  [Connect.t] is the
      connection object. *)

(** {3 Domains} *)

module Domain :
sig
  type 'rw t
    (** Domain handle.  Read-only handles have type [ro Domain.t] and
	read-write handles have type [rw Domain.t].
    *)

  type state =
    | InfoNoState | InfoRunning | InfoBlocked | InfoPaused
    | InfoShutdown | InfoShutoff | InfoCrashed | InfoPMSuspended

  type info = {
    state : state;		        (** running state *)
    max_mem : int64;			(** maximum memory in kilobytes *)
    memory : int64;			(** memory used in kilobytes *)
    nr_virt_cpu : int;			(** number of virtual CPUs *)
    cpu_time : int64;			(** CPU time used in nanoseconds *)
  }

  type vcpu_state = VcpuOffline | VcpuRunning | VcpuBlocked

  type vcpu_info = {
    number : int;			(** virtual CPU number *)
    vcpu_state : vcpu_state;		(** state *)
    vcpu_time : int64;			(** CPU time used in nanoseconds *)
    cpu : int;				(** real CPU number, -1 if offline *)
  }

  type domain_create_flag =
  | START_PAUSED                        (** Launch guest in paused state *)
  | START_AUTODESTROY                   (** Automatically kill guest on close *)
  | START_BYPASS_CACHE                  (** Avoid filesystem cache pollution *)
  | START_FORCE_BOOT                    (** Discard any managed save *)
  | START_VALIDATE                      (** Validate XML against schema *)

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
    | XmlSecure			(** dump security sensitive information too *)
    | XmlInactive		(** dump inactive domain information *)
    | XmlUpdateCPU		(** update guest CPU requirements according to host CPU *)
    | XmlMigratable		(** dump XML suitable for migration *)

  val max_peek : [>`R] t -> int
    (** Maximum size supported by the {!block_peek} and {!memory_peek}
	functions.  If you want to peek more than this then you must
	break your request into chunks. *)

  val create_linux : [>`W] Connect.t -> xml -> rw t
    (** Create a new guest domain (not necessarily a Linux one)
	from the given XML.
	@deprecated Use {!create_xml} instead.
    *)
  val create_xml : [>`W] Connect.t -> xml -> domain_create_flag list -> rw t
    (** Create a new guest domain from the given XML. *)
  val lookup_by_id : 'a Connect.t -> int -> 'a t
    (** Lookup a domain by ID. *)
  val lookup_by_uuid : 'a Connect.t -> uuid -> 'a t
    (** Lookup a domain by UUID.  This uses the packed byte array UUID. *)
  val lookup_by_uuid_string : 'a Connect.t -> string -> 'a t
    (** Lookup a domain by (string) UUID. *)
  val lookup_by_name : 'a Connect.t -> string -> 'a t
    (** Lookup a domain by name. *)
  val destroy : [>`W] t -> unit
    (** Abruptly destroy a domain. *)
  val free : [>`R] t -> unit
    (** [free domain] frees the domain object in memory.

	The domain object is automatically freed if it is garbage
	collected.  This function just forces it to be freed right
	away.
    *)

  val suspend : [>`W] t -> unit
    (** Suspend a domain. *)
  val resume : [>`W] t -> unit
    (** Resume a domain. *)
  val save : [>`W] t -> filename -> unit
    (** Suspend a domain, then save it to the file. *)
  val restore : [>`W] Connect.t -> filename -> unit
    (** Restore a domain from a file. *)
  val core_dump : [>`W] t -> filename -> unit
    (** Force a domain to core dump to the named file. *)
  val shutdown : [>`W] t -> unit
    (** Shutdown a domain. *)
  val reboot : [>`W] t -> unit
    (** Reboot a domain. *)
  val get_name : [>`R] t -> string
    (** Get the domain name. *)
  val get_uuid : [>`R] t -> uuid
    (** Get the domain UUID (as a packed byte array). *)
  val get_uuid_string : [>`R] t -> string
    (** Get the domain UUID (as a printable string). *)
  val get_id : [>`R] t -> int
    (** [get_id dom] returns the ID of the domain.  In most cases
	this returns [-1] if the domain is not running. *)
  val get_os_type : [>`R] t -> string
    (** Get the operating system type. *)
  val get_max_memory : [>`R] t -> int64
    (** Get the maximum memory allocation. *)
  val set_max_memory : [>`W] t -> int64 -> unit
    (** Set the maximum memory allocation. *)
  val set_memory : [>`W] t -> int64 -> unit
    (** Set the normal memory allocation. *)
  val get_info : [>`R] t -> info
    (** Get information about a domain. *)
  val get_xml_desc : [>`R] t -> xml
    (** Get the XML description of a domain. *)
  val get_xml_desc_flags : [>`W] t -> xml_desc_flag list -> xml
    (** Get the XML description of a domain, with the possibility
	to specify flags. *)
  val get_scheduler_type : [>`R] t -> string * int
    (** Get the scheduler type. *)
  val get_scheduler_parameters : [>`R] t -> int -> sched_param array
    (** Get the array of scheduler parameters. *)
  val set_scheduler_parameters : [>`W] t -> sched_param array -> unit
    (** Set the array of scheduler parameters. *)
  val define_xml : [>`W] Connect.t -> xml -> rw t
    (** Define a new domain (but don't start it up) from the XML. *)
  val undefine : [>`W] t -> unit
    (** Undefine a domain - removes its configuration. *)
  val create : [>`W] t -> unit
    (** Launch a defined (inactive) domain. *)
  val get_autostart : [>`R] t -> bool
    (** Get the autostart flag for a domain. *)
  val set_autostart : [>`W] t -> bool -> unit
    (** Set the autostart flag for a domain. *)
  val set_vcpus : [>`W] t -> int -> unit
    (** Change the number of vCPUs available to a domain. *)
  val pin_vcpu : [>`W] t -> int -> string -> unit
    (** [pin_vcpu dom vcpu bitmap] pins a domain vCPU to a bitmap of physical
	CPUs.  See the libvirt documentation for details of the
	layout of the bitmap. *)
  val get_vcpus : [>`R] t -> int -> int -> int * vcpu_info array * string
    (** [get_vcpus dom maxinfo maplen] returns the pinning information
	for a domain.  See the libvirt documentation for details
	of the array and bitmap returned from this function.
    *)
  val get_cpu_stats : [>`R] t -> typed_param list array
    (** [get_pcpu_stats dom] returns the physical CPU stats
	for a domain.  See the libvirt documentation for details.
    *)
  val get_max_vcpus : [>`R] t -> int
    (** Returns the maximum number of vCPUs supported for this domain. *)
  val attach_device : [>`W] t -> xml -> unit
    (** Attach a device (described by the device XML) to a domain. *)
  val detach_device : [>`W] t -> xml -> unit
    (** Detach a device (described by the device XML) from a domain. *)

  val migrate : [>`W] t -> [>`W] Connect.t -> migrate_flag list ->
    ?dname:string -> ?uri:string -> ?bandwidth:int -> unit -> rw t
    (** [migrate dom dconn flags ()] migrates a domain to a
	destination host described by [dconn].

	The optional flag [?dname] is used to rename the domain.

	The optional flag [?uri] is used to route the migration.

	The optional flag [?bandwidth] is used to limit the bandwidth
	used for migration (in Mbps). *)

  val block_stats : [>`R] t -> string -> block_stats
    (** Returns block device stats. *)
  val interface_stats : [>`R] t -> string -> interface_stats
    (** Returns network interface stats. *)

  val block_peek : [>`W] t -> string -> int64 -> int -> string -> int -> unit
    (** [block_peek dom path offset size buf boff] reads [size] bytes at
	[offset] in the domain's [path] block device.

	If successful then the data is written into [buf] starting
	at offset [boff], for [size] bytes.

	See also {!max_peek}. *)
  val memory_peek : [>`W] t -> memory_flag list -> int64 -> int ->
    string -> int -> unit
    (** [memory_peek dom Virtual offset size] reads [size] bytes
	at [offset] in the domain's virtual memory.

	If successful then the data is written into [buf] starting
	at offset [boff], for [size] bytes.

	See also {!max_peek}. *)

  external get_all_domain_stats : [>`R] Connect.t -> stats_type list -> get_all_domain_stats_flag list -> domain_stats_record array = "ocaml_libvirt_domain_get_all_domain_stats"
    (** [get_all_domain_stats conn stats flags] allows you to read
        all stats across multiple/all domains in a single call.

        See the libvirt documentation for
        [virConnectGetAllDomainStats]. *)

  external const : [>`R] t -> ro t = "%identity"
    (** [const dom] turns a read/write domain handle into a read-only
	domain handle.  Note that the opposite operation is impossible.
      *)

  val get_domains : ([>`R] as 'a) Connect.t -> list_flag list -> 'a t list
    (** Get the active and/or inactive domains using the most
	efficient method available.

	See also:
	{!get_domains_and_infos},
	{!Connect.list_domains},
	{!Connect.list_defined_domains}.
  *)

  val get_domains_and_infos : ([>`R] as 'a) Connect.t -> list_flag list ->
    ('a t * info) list
    (** This gets the active and/or inactive domains and the
	domain info for each one using the most efficient
	method available.

	See also:
	{!get_domains},
	{!Connect.list_domains},
	{!Connect.list_defined_domains},
	{!get_info}.
    *)

end
  (** Module dealing with domains.  [Domain.t] is the
      domain object. *)

module Event :
sig

  module Defined : sig
    type t = [
      | `Added          (** Newly created config file *)
      | `Updated        (** Changed config file *)
      | `Unknown of int
    ]

    val to_string: t -> string
  end

  module Undefined : sig
    type t = [
      | `Removed        (** Deleted the config file *)
      | `Unknown of int
    ]

    val to_string: t -> string
  end

  module Started : sig
    type t = [
      | `Booted         (** Normal startup from boot *)
      | `Migrated       (** Incoming migration from another host *)
      | `Restored       (** Restored from a state file *)
      | `FromSnapshot   (** Restored from snapshot *)
      | `Wakeup         (** Started due to wakeup event *)
      | `Unknown of int
    ]

    val to_string: t -> string
  end

  module Suspended : sig
    type t = [
      | `Paused        (** Normal suspend due to admin pause *)
      | `Migrated      (** Suspended for offline migration *)
      | `IOError       (** Suspended due to a disk I/O error *)
      | `Watchdog      (** Suspended due to a watchdog firing *)
      | `Restored      (** Restored from paused state file *)
      | `FromSnapshot  (** Restored from paused snapshot *)
      | `APIError      (** suspended after failure during libvirt API call *)
      | `Unknown of int
    ]

    val to_string: t -> string
  end

  module Resumed : sig
    type t = [
      | `Unpaused      (** Normal resume due to admin unpause *)
      | `Migrated      (** Resumed for completion of migration *)
      | `FromSnapshot  (** Resumed from snapshot *)
      | `Unknown of int
    ]

    val to_string: t -> string
  end

  module Stopped : sig
    type t = [
      | `Shutdown     (** Normal shutdown *)
      | `Destroyed    (** Forced poweroff from host *)
      | `Crashed      (** Guest crashed *)
      | `Migrated     (** Migrated off to another host *)
      | `Saved        (** Saved to a state file *)
      | `Failed       (** Host emulator/mgmt failed *)
      | `FromSnapshot (** offline snapshot loaded *)
      | `Unknown of int
    ]

    val to_string: t -> string
  end

  module PM_suspended : sig
    type t = [
      | `Memory       (** Guest was PM suspended to memory *)
      | `Disk         (** Guest was PM suspended to disk *)
      | `Unknown of int
    ]

    val to_string: t -> string
  end

  module Lifecycle : sig
    type t = [
      | `Defined of Defined.t
      | `Undefined of Undefined.t
      | `Started of Started.t
      | `Suspended of Suspended.t
      | `Resumed of Resumed.t
      | `Stopped of Stopped.t
      | `Shutdown (* no detail defined yet *)
      | `PMSuspended of PM_suspended.t
      | `Unknown of int
    ]

    val to_string: t -> string
  end

  module Reboot : sig
    type t = unit

    val to_string: t -> string
  end

  module Rtc_change : sig
    type t = int64

    val to_string: t -> string
  end

  module Watchdog : sig
    type t = [
      | `None           (** No action, watchdog ignored *)
      | `Pause          (** Guest CPUs are paused *)
      | `Reset          (** Guest CPUs are reset *)
      | `Poweroff       (** Guest is forcably powered off *)
      | `Shutdown       (** Guest is requested to gracefully shutdown *)
      | `Debug          (** No action, a debug message logged *)
      | `Unknown of int (** newer libvirt *)
    ]

    val to_string: t -> string
  end

  module Io_error : sig
    (** Represents both IOError and IOErrorReason *)
    type action = [
      | `None           (** No action, IO error ignored *)
      | `Pause          (** Guest CPUs are paused *)
      | `Report         (** IO error reported to guest OS *)
      | `Unknown of int (** newer libvirt *)
    ]

    type t = {
      src_path: string option;  (** The host file on which the I/O error occurred *)
      dev_alias: string option; (** The guest device alias associated with the path *)
      action: action;    (** The action that is to be taken due to the IO error *)
      reason: string option;    (** The cause of the IO error *)
    }

    val to_string: t -> string
  end

  module Graphics_address : sig
    type family = [
      | `Ipv4           (** IPv4 address *)
      | `Ipv6           (** IPv6 address *)
      | `Unix           (** UNIX socket path *)
      | `Unknown of int (** newer libvirt *)
    ]

    type t = {
      family: family;         (** Address family *)
      node: string option;    (** Address of node (eg IP address, or UNIX path *)
      service: string option; (** Service name/number (eg TCP port, or NULL) *)
    }

    val to_string: t -> string
  end

  module Graphics_subject : sig
    type identity = {
      ty: string option;   (** Type of identity *)
      name: string option; (** Identity value *)
    }

    type t = identity list

    val to_string: t -> string
  end

  module Graphics : sig
    type phase = [
      | `Connect        (** Initial socket connection established *)
      | `Initialize     (** Authentication & setup completed *)
      | `Disconnect     (** Final socket disconnection *)
      | `Unknown of int (** newer libvirt *)
    ]

    type t = {
      phase: phase;                (** the phase of the connection *)
      local: Graphics_address.t;   (** the local server address *)
      remote: Graphics_address.t;  (** the remote client address *)
      auth_scheme: string option;  (** the authentication scheme activated *)
      subject: Graphics_subject.t; (** the authenticated subject (user) *)
    }

    val to_string: t -> string
  end

  module Control_error : sig
    type t = unit

    val to_string: t -> string
  end

  module Block_job : sig
    type ty = [
      | `KnownUnknown (** explicitly named UNKNOWN in the spec *)
      | `Pull
      | `Copy
      | `Commit
      | `Unknown of int
    ]

    type status = [
      | `Completed
      | `Failed
      | `Cancelled
      | `Ready
      | `Unknown of int
    ]

    type t = {
      disk: string option; (** fully-qualified name of the affected disk *)	
      ty: ty;              (** type of block job *)
      status: status;      (** final status of the operation *)
    }

    val to_string: t -> string
  end

  module Disk_change : sig
    type reason = [
      | `MissingOnStart
      | `Unknown of int
    ]

    type t = {
      old_src_path: string option; (** old source path *)
      new_src_path: string option; (** new source path *)
      dev_alias: string option;    (** device alias name *)
      reason: reason;              (** reason why this callback was called *)
    }

    val to_string: t -> string
  end

  module Tray_change : sig
    type reason = [
      | `Open
      | `Close
      | `Unknown of int
    ]

    type t = {
      dev_alias: string option; (** device alias *)
      reason: reason;           (** why the tray status was changed *)
    }

    val to_string: t -> string
  end

  module PM_wakeup : sig
    type reason = [
      | `Unknown of int
    ]

    type t = reason

    val to_string: t -> string
  end

  module PM_suspend : sig
    type reason = [
      | `Unknown of int
    ]

    type t = reason

    val to_string: t -> string
  end

  module Balloon_change : sig
    type t = int64

    val to_string: t -> string
  end

  module PM_suspend_disk : sig
    type reason = [
      | `Unknown of int
    ]

    type t = reason

    val to_string: t -> string
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

    (** type of a registered call back function *)

  val register_default_impl : unit -> unit
    (** Registers the default event loop based on poll(). This
        must be done before connections are opened.

        Once registered call run_default_impl in a loop. *)

  val run_default_impl : unit -> unit
    (** Runs one iteration of the event loop. Applications will
        generally want to have a thread which invokes this in an
        infinite loop. *)

  type callback_id
    (** an individual event registration *)

  val register_any : 'a Connect.t -> ?dom:'a Domain.t -> callback -> callback_id
    (** [register_any con ?dom callback] registers [callback]
        to receive notification of arbitrary domain events. Return
        a registration id which can be used in [deregister_any].

        If [?dom] is [None] then register for this kind of event on
        all domains. If [dom] is [Some d] then register for this
        kind of event only on [d].
    *)

  val deregister_any : 'a Connect.t -> callback_id -> unit
    (** [deregister_any con id] deregisters the previously registered
        callback with id [id]. *)

  type timer_id
    (** an individual timer event *)

  val add_timeout : 'a Connect.t -> int -> (unit -> unit) -> timer_id
    (** [add_timeout con ms cb] registers [cb] as a timeout callback
        which will be called every [ms] milliseconds *)

  val remove_timeout : 'a Connect.t -> timer_id -> unit
    (** [remove_timeout con t] deregisters timeout callback [t]. *)

end
  (** Module dealing with events generated by domain
      state changes. *)

(** {3 Networks} *)

module Network : 
sig
  type 'rw t
    (** Network handle.  Read-only handles have type [ro Network.t] and
	read-write handles have type [rw Network.t].
    *)

  val lookup_by_name : 'a Connect.t -> string -> 'a t
    (** Lookup a network by name. *)
  val lookup_by_uuid : 'a Connect.t -> uuid -> 'a t
    (** Lookup a network by (packed) UUID. *)
  val lookup_by_uuid_string : 'a Connect.t -> string -> 'a t
    (** Lookup a network by UUID string. *)
  val create_xml : [>`W] Connect.t -> xml -> rw t
    (** Create a network. *)
  val define_xml : [>`W] Connect.t -> xml -> rw t
    (** Define but don't activate a network. *)
  val undefine : [>`W] t -> unit
    (** Undefine configuration of a network. *)
  val create : [>`W] t -> unit
    (** Start up a defined (inactive) network. *)
  val destroy : [>`W] t -> unit
    (** Destroy a network. *)
  val free : [>`R] t -> unit
    (** [free network] frees the network object in memory.

	The network object is automatically freed if it is garbage
	collected.  This function just forces it to be freed right
	away.
    *)

  val get_name : [>`R] t -> string
    (** Get network name. *)
  val get_uuid : [>`R] t -> uuid
    (** Get network packed UUID. *)
  val get_uuid_string : [>`R] t -> string
    (** Get network UUID as a printable string. *)
  val get_xml_desc : [>`R] t -> xml
    (** Get XML description of a network. *)
  val get_bridge_name : [>`R] t -> string
    (** Get bridge device name of a network. *)
  val get_autostart : [>`R] t -> bool
    (** Get the autostart flag for a network. *)
  val set_autostart : [>`W] t -> bool -> unit
    (** Set the autostart flag for a network. *)

  external const : [>`R] t -> ro t = "%identity"
    (** [const network] turns a read/write network handle into a read-only
	network handle.  Note that the opposite operation is impossible.
      *)
end
  (** Module dealing with networks.  [Network.t] is the
      network object. *)

(** {3 Storage pools} *)

module Pool :
sig
  type 'rw t
    (** Storage pool handle. *)

  type pool_state = Inactive | Building | Running | Degraded | Inaccessible
    (** State of the storage pool. *)

  type pool_build_flags = New | Repair | Resize
    (** Flags for creating a storage pool. *)

  type pool_delete_flags = Normal | Zeroed
    (** Flags for deleting a storage pool. *)

  type pool_info = {
    state : pool_state;			(** Pool state. *)
    capacity : int64;			(** Logical size in bytes. *)
    allocation : int64;			(** Currently allocated in bytes. *)
    available : int64;			(** Remaining free space bytes. *)
  }

  val lookup_by_name : 'a Connect.t -> string -> 'a t
  val lookup_by_uuid : 'a Connect.t -> uuid -> 'a t
  val lookup_by_uuid_string : 'a Connect.t -> string -> 'a t
    (** Look up a storage pool by name, UUID or UUID string. *)

  val create_xml : [>`W] Connect.t -> xml -> rw t
    (** Create a storage pool. *)
  val define_xml : [>`W] Connect.t -> xml -> rw t
    (** Define but don't activate a storage pool. *)
  val build : [>`W] t -> pool_build_flags -> unit
    (** Build a storage pool. *)
  val undefine : [>`W] t -> unit
    (** Undefine configuration of a storage pool. *)
  val create : [>`W] t -> unit
    (** Start up a defined (inactive) storage pool. *)
  val destroy : [>`W] t -> unit
    (** Destroy a storage pool. *)
  val delete : [>`W] t -> unit
    (** Delete a storage pool. *)
  val free : [>`R] t -> unit
    (** Free a storage pool object in memory.

	The storage pool object is automatically freed if it is garbage
	collected.  This function just forces it to be freed right
	away.
    *)
  val refresh : [`R] t -> unit
    (** Refresh the list of volumes in the storage pool. *)

  val get_name : [`R] t -> string
    (** Name of the pool. *)
  val get_uuid : [`R] t -> uuid
    (** Get the UUID (as a packed byte array). *)
  val get_uuid_string : [`R] t -> string
    (** Get the UUID (as a printable string). *)
  val get_info : [`R] t -> pool_info
    (** Get information about the pool. *)
  val get_xml_desc : [`R] t -> xml
    (** Get the XML description. *)
  val get_autostart : [`R] t -> bool
    (** Get the autostart flag for the storage pool. *)
  val set_autostart : [>`W] t -> bool -> unit
    (** Set the autostart flag for the storage pool. *)

  val num_of_volumes : [`R] t -> int
    (** Returns the number of storage volumes within the storage pool. *)
  val list_volumes : [`R] t -> int -> string array
    (** Return list of storage volumes. *)

  external const : [>`R] t -> ro t = "%identity"
    (** [const conn] turns a read/write storage pool into a read-only
	pool.  Note that the opposite operation is impossible.
      *)
end
  (** Module dealing with storage pools. *)

(** {3 Storage volumes} *)

module Volume :
sig
  type 'rw t
    (** Storage volume handle. *)

  type vol_type = File | Block | Dir | Network | NetDir | Ploop
    (** Type of a storage volume. *)

  type vol_delete_flags = Normal | Zeroed
    (** Flags for deleting a storage volume. *)

  type vol_info = {
    typ : vol_type;			(** Type of storage volume. *)
    capacity : int64;			(** Logical size in bytes. *)
    allocation : int64;			(** Currently allocated in bytes. *)
  }

  val lookup_by_name : 'a Pool.t -> string -> 'a t
  val lookup_by_key : 'a Connect.t -> string -> 'a t
  val lookup_by_path : 'a Connect.t -> string -> 'a t
    (** Look up a storage volume by name, key or path volume. *)

  val pool_of_volume : 'a t -> 'a Pool.t
    (** Get the storage pool containing this volume. *)

  val get_name : [`R] t -> string
    (** Name of the volume. *)
  val get_key : [`R] t -> string
    (** Key of the volume. *)
  val get_path : [`R] t -> string
    (** Path of the volume. *)
  val get_info : [`R] t -> vol_info
    (** Get information about the storage volume. *)
  val get_xml_desc : [`R] t -> xml
    (** Get the XML description. *)

  val create_xml : [>`W] Pool.t -> xml -> unit
    (** Create a storage volume. *)
  val delete : [>`W] t -> vol_delete_flags -> unit
    (** Delete a storage volume. *)
  val free : [>`R] t -> unit
    (** Free a storage volume object in memory.

	The storage volume object is automatically freed if it is garbage
	collected.  This function just forces it to be freed right
	away.
    *)

  external const : [>`R] t -> ro t = "%identity"
    (** [const conn] turns a read/write storage volume into a read-only
	volume.  Note that the opposite operation is impossible.
      *)
end
  (** Module dealing with storage volumes. *)

(** {3 Secrets} *)

module Secret :
sig
  type 'rw t
    (** Secret handle. *)

  type secret_usage_type =
    | NoType
    | Volume
    | Ceph
    | ISCSI
    | TLS
    (** Usage type of a secret. *)

  val lookup_by_uuid : 'a Connect.t -> uuid -> 'a t
    (** Lookup a secret by UUID.  This uses the packed byte array UUID. *)
  val lookup_by_uuid_string : 'a Connect.t -> string -> 'a t
    (** Lookup a secret by (string) UUID. *)
  val lookup_by_usage : 'a Connect.t -> secret_usage_type -> string -> 'a t
    (** Lookup a secret by usage type, and usage ID. *)

  val define_xml : [>`W] Connect.t -> xml -> rw t
    (** Define a secret. *)

  val get_uuid : [>`R] t -> uuid
    (** Get the UUID (as a packed byte array) of the secret. *)
  val get_uuid_string : [>`R] t -> string
    (** Get the UUID (as a printable string) of the secret. *)
  val get_usage_type : [>`R] t -> secret_usage_type
    (** Get the usage type of the secret. *)
  val get_usage_id : [>`R] t -> string
    (** Get the usage ID of the secret. *)
  val get_xml_desc : [>`R] t -> xml
    (** Get the XML description. *)

  val set_value : [>`W] t -> bytes -> unit
    (** Set a new value for the secret. *)
  val get_value : [>`R] t -> bytes
    (** Get the value of the secret. *)

  val undefine : [>`W] t -> unit
    (** Undefine a secret. *)

  val free : [>`R] t -> unit
    (** Free a secret object in memory.

	The secret object is automatically freed if it is garbage
	collected.  This function just forces it to be freed right
	away.
    *)

  external const : [>`R] t -> ro t = "%identity"
    (** [const conn] turns a read/write secret into a read-only
	secret.  Note that the opposite operation is impossible.
      *)
end
  (** Module dealing with secrets. *)

(** {3 Error handling and exceptions} *)

module Virterror :
sig
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
	(* ^^ NB: If you add a variant you MUST edit
	   libvirt_c_epilogue.c:MAX_VIR_* *)
    | VIR_ERR_UNKNOWN of int (** Other error, not handled with existing values. *)
	(** See [<libvirt/virterror.h>] for meaning of these codes. *)

  val string_of_code : code -> string

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
	(* ^^ NB: If you add a variant you MUST edit
	   libvirt_c_epilogue.c: MAX_VIR_* *)
    | VIR_FROM_UNKNOWN of int (** Other domain, not handled with existing values. *)
	(** Subsystem / driver which produced the error. *)

  val string_of_domain : domain -> string

  type level =
    | VIR_ERR_NONE
    | VIR_ERR_WARNING
    | VIR_ERR_ERROR
	(* ^^ NB: If you add a variant you MUST edit libvirt_c.c: MAX_VIR_* *)
    | VIR_ERR_UNKNOWN_LEVEL of int (** Other level, not handled with existing values. *)
	(** No error, a warning or an error. *)

  val string_of_level : level -> string

  type t = {
    code : code;			(** Error code. *)
    domain : domain;			(** Origin of the error. *)
    message : string option;		(** Human-readable message. *)
    level : level;			(** Error or warning. *)
    str1 : string option;		(** Informational string. *)
    str2 : string option;		(** Informational string. *)
    str3 : string option;		(** Informational string. *)
    int1 : int32;			(** Informational integer. *)
    int2 : int32;			(** Informational integer. *)
  }
    (** An error object. *)

  val to_string : t -> string
    (** Turn the exception into a printable string. *)

  val get_last_error : unit -> t option
  val get_last_conn_error : [>`R] Connect.t -> t option
    (** Get the last error at a global or connection level.

	Normally you do not need to use these functions because
	the library automatically turns errors into exceptions.
    *)

  val reset_last_error : unit -> unit
  val reset_last_conn_error : [>`R] Connect.t -> unit
    (** Reset the error at a global or connection level.

	Normally you do not need to use these functions.
    *)

  val no_error : unit -> t
    (** Creates an empty error message.

	Normally you do not need to use this function.
    *)
end
  (** Module dealing with errors. *)

exception Virterror of Virterror.t
(** This exception can be raised by any library function that detects
    an error.  To get a printable error message, call
    {!Virterror.to_string} on the content of this exception.
*)

exception Not_supported of string
(**
    Functions may raise
    [Not_supported "virFoo"]
    (where [virFoo] is the libvirt function name) if a function is
    not supported at either compile or run time.  This applies to
    any libvirt function added after version 0.2.1.

    See also {{:https://libvirt.org/hvsupport.html}https://libvirt.org/hvsupport.html}
*)

(** {3 Utility functions} *)

val map_ignore_errors : ('a -> 'b) -> 'a list -> 'b list
(** [map_ignore_errors f xs] calls function [f] for each element of [xs].

    This is just like [List.map] except that if [f x] throws a
    {!Virterror.t} exception, the error is ignored and [f x]
    is not returned in the final list.

    This function is primarily useful when dealing with domains which
    might 'disappear' asynchronously from the currently running
    program.
*)
