/* OCaml bindings for libvirt.
 * (C) Copyright 2007 Richard W.M. Jones, Red Hat Inc.
 * https://libvirt.org/
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version,
 * with the OCaml linking exception described in ../COPYING.LIB.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 */

/* Please read libvirt/README file. */

static const char *Optstring_val (value strv);
typedef value (*Val_ptr_t) (void *);
static value Val_opt (void *ptr, Val_ptr_t Val_ptr);
typedef value (*Val_const_ptr_t) (const void *);
static value Val_opt_const (const void *ptr, Val_const_ptr_t Val_ptr);
/*static value option_default (value option, value deflt);*/
static void _raise_virterror (const char *fn) Noreturn;
static value Val_virterror (virErrorPtr err);
static int _list_length (value listv);
static value Val_virconnectcredential (const virConnectCredentialPtr cred);

/* Use this around synchronous libvirt API calls to release the OCaml
 * lock, allowing other threads to run simultaneously.  'code' must not
 * perform any caml_* calls, run any OCaml code, or raise any exception.
 * https://web.archive.org/web/20030521020915/http://caml.inria.fr/archives/200106/msg00199.html
 */
#define NONBLOCKING(code)			\
  do {						\
    caml_enter_blocking_section ();		\
    code;					\
    caml_leave_blocking_section ();		\
  } while (0)

/* Empty macro to use as empty parameter for other macros, since
 * a null token as parameter when calling a macro is not allowed
 * before C99.
 */
#define EMPTY
/* Check error condition from a libvirt function, and automatically raise
 * an exception if one is found.
 */
#define CHECK_ERROR_CLEANUP(cond, cleanup, fn) \
  do { if (cond) { cleanup; _raise_virterror (fn); } } while (0)
#define CHECK_ERROR(cond, fn) \
  CHECK_ERROR_CLEANUP(cond, EMPTY, fn)

/*----------------------------------------------------------------------*/

/* Some notes about the use of custom blocks to store virConnectPtr,
 * virDomainPtr and virNetworkPtr.
 *------------------------------------------------------------------
 *
 * Libvirt does some tricky reference counting to keep track of
 * virConnectPtr's, virDomainPtr's and virNetworkPtr's.
 *
 * There is only one function which can return a virConnectPtr
 * (virConnectOpen*) and that allocates a new one each time.
 *
 * virDomainPtr/virNetworkPtr's on the other hand can be returned
 * repeatedly (for the same underlying domain/network), and we must
 * keep track of each one and explicitly free it with virDomainFree
 * or virNetworkFree.  If we lose track of one then the reference
 * counting in libvirt will keep it open.  We therefore wrap these
 * in a custom block with a finalizer function.
 *
 * We also have to allow the user to explicitly free them, in
 * which case we set the pointer inside the custom block to NULL.
 * The finalizer notices this and doesn't free the object.
 *
 * Domains and networks "belong to" a connection.  We have to avoid
 * the situation like this:
 *
 *   let conn = Connect.open ... in
 *   let dom = Domain.lookup_by_id conn 0 in
 *   (* conn goes out of scope and is garbage collected *)
 *   printf "dom name = %s\n" (Domain.get_name dom)
 *
 * The reason is that when conn is garbage collected, virConnectClose
 * is called and any subsequent operations on dom will fail (in fact
 * will probably segfault).  To stop this from happening, the OCaml
 * wrappers store domains (and networks) as explicit (dom, conn)
 * pairs.
 *
 * Update 2008/01: Storage pools and volumes work the same way as
 * domains and networks.
 */

/* Unwrap a custom block. */
#define Connect_val(rv) (*((virConnectPtr *)Data_custom_val(rv)))
#define Dom_val(rv) (*((virDomainPtr *)Data_custom_val(rv)))
#define Net_val(rv) (*((virNetworkPtr *)Data_custom_val(rv)))
#define Pol_val(rv) (*((virStoragePoolPtr *)Data_custom_val(rv)))
#define Vol_val(rv) (*((virStorageVolPtr *)Data_custom_val(rv)))
#define Sec_val(rv) (*((virSecretPtr *)Data_custom_val(rv)))

/* Wrap up a pointer to something in a custom block. */
static value Val_connect (virConnectPtr conn);
static value Val_dom (virDomainPtr dom);
static value Val_net (virNetworkPtr net);
static value Val_pol (virStoragePoolPtr pool);
static value Val_vol (virStorageVolPtr vol);
static value Val_sec (virSecretPtr sec);

/* Domains and networks are stored as pairs (dom/net, conn), so have
 * some convenience functions for unwrapping and wrapping them.
 */
#define Domain_val(rv) (Dom_val(Field((rv),0)))
#define Network_val(rv) (Net_val(Field((rv),0)))
#define Pool_val(rv) (Pol_val(Field((rv),0)))
#define Volume_val(rv) (Vol_val(Field((rv),0)))
#define Secret_val(rv) (Sec_val(Field((rv),0)))
#define Connect_domv(rv) (Connect_val(Field((rv),1)))
#define Connect_netv(rv) (Connect_val(Field((rv),1)))
#define Connect_polv(rv) (Connect_val(Field((rv),1)))
#define Connect_volv(rv) (Connect_val(Field((rv),1)))
#define Connect_secv(rv) (Connect_val(Field((rv),1)))

static value Val_domain (virDomainPtr dom, value connv);
static value Val_network (virNetworkPtr net, value connv);
static value Val_pool (virStoragePoolPtr pol, value connv);
static value Val_volume (virStorageVolPtr vol, value connv);
static value Val_secret (virSecretPtr sec, value connv);
