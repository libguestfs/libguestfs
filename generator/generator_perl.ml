(* libguestfs
 * Copyright (C) 2009-2012 Red Hat Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

(* Please read generator/README first. *)

open Printf

open Generator_types
open Generator_utils
open Generator_pr
open Generator_docstrings
open Generator_optgroups
open Generator_actions
open Generator_structs
open Generator_c
open Generator_events

(* Generate Perl xs code, a sort of crazy variation of C with macros. *)
let rec generate_perl_xs () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>

#include \"EXTERN.h\"
#include \"perl.h\"
#include \"XSUB.h\"

#include <guestfs.h>

#define STREQ(a,b) (strcmp((a),(b)) == 0)

static SV *
my_newSVll(long long val) {
#ifdef USE_64_BIT_ALL
  return newSViv(val);
#else
  char buf[100];
  int len;
  len = snprintf(buf, 100, \"%%\" PRId64, val);
  return newSVpv(buf, len);
#endif
}

static SV *
my_newSVull(unsigned long long val) {
#ifdef USE_64_BIT_ALL
  return newSVuv(val);
#else
  char buf[100];
  int len;
  len = snprintf(buf, 100, \"%%\" PRIu64, val);
  return newSVpv(buf, len);
#endif
}

/* Convert a 64 bit int on input.  To cope with the case of having
 * a 32 bit Perl interpreter, we allow the user to pass a string
 * here which is scanned as a 64 bit integer.
 */
static int64_t
my_SvIV64 (SV *sv)
{
#ifdef USE_64_BIT_ALL
  return SvIV (sv);
#else
  if (SvTYPE (sv) == SVt_PV) {
    const char *str = SvPV_nolen (sv);
    int64_t r;

    sscanf (str, \"%%\" SCNi64, &r);
    return r;
  }
  else
    return SvIV (sv);
#endif
}

/* http://www.perlmonks.org/?node_id=680842 */
static char **
XS_unpack_charPtrPtr (SV *arg) {
  char **ret;
  AV *av;
  I32 i;

  if (!arg || !SvOK (arg) || !SvROK (arg) || SvTYPE (SvRV (arg)) != SVt_PVAV)
    croak (\"array reference expected\");

  av = (AV *)SvRV (arg);
  ret = malloc ((av_len (av) + 1 + 1) * sizeof (char *));
  if (!ret)
    croak (\"malloc failed\");

  for (i = 0; i <= av_len (av); i++) {
    SV **elem = av_fetch (av, i, 0);

    if (!elem || !*elem)
      croak (\"missing element in list\");

    ret[i] = SvPV_nolen (*elem);
  }

  ret[i] = NULL;

  return ret;
}

/* http://www.perlmonks.org/?node=338857 */
static void
_event_callback_wrapper (guestfs_h *g,
                         void *cb,
                         uint64_t event,
                         int event_handle,
                         int flags,
                         const char *buf, size_t buf_len,
                         const uint64_t *array, size_t array_len)
{
  dSP;
  ENTER;
  SAVETMPS;
  PUSHMARK (SP);
  XPUSHs (sv_2mortal (my_newSVull (event)));
  XPUSHs (sv_2mortal (newSViv (event_handle)));
  XPUSHs (sv_2mortal (newSVpvn (buf ? buf : \"\", buf_len)));
  AV *av = newAV ();
  size_t i;
  for (i = 0; i < array_len; ++i)
    av_push (av, my_newSVull (array[i]));
  XPUSHs (sv_2mortal (newRV ((SV *) av)));
  PUTBACK;
  call_sv ((SV *) cb, G_VOID | G_DISCARD | G_EVAL);
  FREETMPS;
  LEAVE;
}

static SV **
get_all_event_callbacks (guestfs_h *g, size_t *len_rtn)
{
  SV **r;
  size_t i;
  const char *key;
  SV *cb;

  /* Count the length of the array that will be needed. */
  *len_rtn = 0;
  cb = guestfs_first_private (g, &key);
  while (cb != NULL) {
    if (strncmp (key, \"_perl_event_\", strlen (\"_perl_event_\")) == 0)
      (*len_rtn)++;
    cb = guestfs_next_private (g, &key);
  }

  /* Copy them into the return array. */
  r = guestfs_safe_malloc (g, sizeof (SV *) * (*len_rtn));

  i = 0;
  cb = guestfs_first_private (g, &key);
  while (cb != NULL) {
    if (strncmp (key, \"_perl_event_\", strlen (\"_perl_event_\")) == 0) {
      r[i] = cb;
      i++;
    }
    cb = guestfs_next_private (g, &key);
  }

  return r;
}

static void
_close_handle (guestfs_h *g)
{
  size_t i, len;
  SV **cbs;

  assert (g != NULL);

  /* As in the OCaml bindings, there is a hard to solve case where the
   * caller can delete a callback from within the callback, resulting
   * in a double-free here.  XXX
   */
  cbs = get_all_event_callbacks (g, &len);

  guestfs_close (g);

  for (i = 0; i < len; ++i)
    SvREFCNT_dec (cbs[i]);
  free (cbs);
}

MODULE = Sys::Guestfs  PACKAGE = Sys::Guestfs

PROTOTYPES: ENABLE

guestfs_h *
_create ()
   CODE:
      RETVAL = guestfs_create ();
      if (!RETVAL)
        croak (\"could not create guestfs handle\");
      guestfs_set_error_handler (RETVAL, NULL, NULL);
 OUTPUT:
      RETVAL

void
DESTROY (sv)
      SV *sv;
 PPCODE:
      /* For the 'g' argument above we do the conversion explicitly and
       * don't rely on the typemap, because if the handle has been
       * explicitly closed we don't want the typemap conversion to
       * display an error.
       */
      HV *hv = (HV *) SvRV (sv);
      SV **svp = hv_fetch (hv, \"_g\", 2, 0);
      if (svp != NULL) {
        guestfs_h *g = (guestfs_h *) SvIV (*svp);
        _close_handle (g);
      }

void
close (g)
      guestfs_h *g;
 PPCODE:
      _close_handle (g);
      /* Avoid double-free in DESTROY method. */
      HV *hv = (HV *) SvRV (ST(0));
      (void) hv_delete (hv, \"_g\", 2, G_DISCARD);

SV *
set_event_callback (g, cb, event_bitmask)
      guestfs_h *g;
      SV *cb;
      int event_bitmask;
PREINIT:
      int eh;
      char key[64];
   CODE:
      eh = guestfs_set_event_callback (g, _event_callback_wrapper,
                                       event_bitmask, 0, cb);
      if (eh == -1)
        croak (\"%%s\", guestfs_last_error (g));

      /* Increase the refcount for this callback, since we are storing
       * it in the opaque C libguestfs handle.  We need to remember that
       * we did this, so we can decrease the refcount for all undeleted
       * callbacks left around at close time (see _close_handle).
       */
      SvREFCNT_inc (cb);

      snprintf (key, sizeof key, \"_perl_event_%%d\", eh);
      guestfs_set_private (g, key, cb);

      RETVAL = newSViv (eh);
 OUTPUT:
      RETVAL

void
delete_event_callback (g, event_handle)
      guestfs_h *g;
      int event_handle;
PREINIT:
      char key[64];
      SV *cb;
   CODE:
      snprintf (key, sizeof key, \"_perl_event_%%d\", event_handle);
      cb = guestfs_get_private (g, key);
      if (cb) {
        SvREFCNT_dec (cb);
        guestfs_set_private (g, key, NULL);
        guestfs_delete_event_callback (g, event_handle);
      }

SV *
last_errno (g)
      guestfs_h *g;
PREINIT:
      int errnum;
   CODE:
      errnum = guestfs_last_errno (g);
      RETVAL = newSViv (errnum);
 OUTPUT:
      RETVAL

void
user_cancel (g)
      guestfs_h *g;
 PPCODE:
      guestfs_user_cancel (g);

";

  List.iter (
    fun (name, (ret, args, optargs as style), _, _, _, _, _) ->
      (match ret with
       | RErr -> pr "void\n"
       | RInt _ -> pr "SV *\n"
       | RInt64 _ -> pr "SV *\n"
       | RBool _ -> pr "SV *\n"
       | RConstString _ -> pr "SV *\n"
       | RConstOptString _ -> pr "SV *\n"
       | RString _ -> pr "SV *\n"
       | RBufferOut _ -> pr "SV *\n"
       | RStringList _
       | RStruct _ | RStructList _
       | RHashtable _ ->
           pr "void\n" (* all lists returned implictly on the stack *)
      );
      (* Call and arguments. *)
      pr "%s (g" name;
      List.iter (
        fun arg -> pr ", %s" (name_of_argt arg)
      ) args;
      if optargs <> [] then
        pr ", ...";
      pr ")\n";
      pr "      guestfs_h *g;\n";
      iteri (
        fun i ->
          function
          | Pathname n | Device n | Dev_or_Path n | String n
          | FileIn n | FileOut n | Key n ->
              pr "      char *%s;\n" n
          | BufferIn n ->
              pr "      char *%s;\n" n;
              pr "      size_t %s_size = SvCUR (ST(%d));\n" n (i+1)
          | OptString n ->
              (* http://www.perlmonks.org/?node_id=554277
               * Note that the implicit handle argument means we have
               * to add 1 to the ST(x) operator.
               *)
              pr "      char *%s = SvOK(ST(%d)) ? SvPV_nolen(ST(%d)) : NULL;\n" n (i+1) (i+1)
          | StringList n | DeviceList n -> pr "      char **%s;\n" n
          | Bool n -> pr "      int %s;\n" n
          | Int n -> pr "      int %s;\n" n
          | Int64 n -> pr "      int64_t %s;\n" n
          | Pointer (t, n) -> pr "      %s %s;\n" t n
      ) args;

      (* PREINIT section (local variable declarations). *)
      pr "PREINIT:\n";
      (match ret with
       | RErr ->
           pr "      int r;\n";
       | RInt _
       | RBool _ ->
           pr "      int r;\n";
       | RInt64 _ ->
           pr "      int64_t r;\n";
       | RConstString _ ->
           pr "      const char *r;\n";
       | RConstOptString _ ->
           pr "      const char *r;\n";
       | RString _ ->
           pr "      char *r;\n";
       | RStringList _ | RHashtable _ ->
           pr "      char **r;\n";
           pr "      size_t i, n;\n";
       | RStruct (_, typ) ->
           pr "      struct guestfs_%s *r;\n" typ;
       | RStructList (_, typ) ->
           pr "      struct guestfs_%s_list *r;\n" typ;
           pr "      size_t i;\n";
           pr "      HV *hv;\n";
       | RBufferOut _ ->
           pr "      char *r;\n";
           pr "      size_t size;\n";
      );

      if optargs <> [] then (
        pr "      struct guestfs_%s_argv optargs_s = { .bitmask = 0 };\n" name;
        pr "      struct guestfs_%s_argv *optargs = &optargs_s;\n" name;
        pr "      size_t items_i;\n";
      );

      (* CODE or PPCODE section.  PPCODE is used where we are
       * returning void, or where we push the return value on the stack
       * ourselves.  Using CODE means we will manipulate RETVAL.
       *)
      (match ret with
       | RErr ->
           pr " PPCODE:\n";
       | RInt n
       | RBool n ->
           pr "   CODE:\n";
       | RInt64 n ->
           pr "   CODE:\n";
       | RConstString n ->
           pr "   CODE:\n";
       | RConstOptString n ->
           pr "   CODE:\n";
       | RString n ->
           pr "   CODE:\n";
       | RStringList n | RHashtable n ->
           pr " PPCODE:\n";
       | RBufferOut n ->
           pr "   CODE:\n";
       | RStruct _
       | RStructList _ ->
           pr " PPCODE:\n";
      );

      (* For optional arguments, convert these from the XSUB "items"
       * variable by hand.
       *)
      if optargs <> [] then (
        let uc_name = String.uppercase name in
        let skip = List.length args + 1 in
        pr "      if (((items - %d) & 1) != 0)\n" skip;
        pr "        croak (\"expecting an even number of extra parameters\");\n";
        pr "      for (items_i = %d; items_i < items; items_i += 2) {\n" skip;
        pr "        uint64_t this_mask;\n";
        pr "        const char *this_arg;\n";
        pr "\n";
        pr "        this_arg = SvPV_nolen (ST (items_i));\n";
        pr "        ";
        List.iter (
          fun argt ->
            let n = name_of_optargt argt in
            let uc_n = String.uppercase n in
            pr "if (STREQ (this_arg, \"%s\")) {\n" n;
            pr "          optargs_s.%s = " n;
            (match argt with
             | OBool _
             | OInt _ -> pr "SvIV (ST (items_i+1))"
             | OInt64 _ -> pr "my_SvIV64 (ST (items_i+1))"
             | OString _ -> pr "SvPV_nolen (ST (items_i+1))"
            );
            pr ";\n";
            pr "          this_mask = GUESTFS_%s_%s_BITMASK;\n" uc_name uc_n;
            pr "        }\n";
            pr "        else ";
        ) optargs;
        pr "croak (\"unknown optional argument '%%s'\", this_arg);\n";
        pr "        if (optargs_s.bitmask & this_mask)\n";
        pr "          croak (\"optional argument '%%s' given twice\",\n";
        pr "                 this_arg);\n";
        pr "        optargs_s.bitmask |= this_mask;\n";
        pr "      }\n";
        pr "\n";
      );

      (* The call to the C function. *)
      if optargs = [] then
        pr "      r = guestfs_%s " name
      else
        pr "      r = guestfs_%s_argv " name;
      generate_c_call_args ~handle:"g" style;
      pr ";\n";

      (* Cleanup any arguments. *)
      List.iter (
        function
        | Pathname _ | Device _ | Dev_or_Path _ | String _ | OptString _
        | Bool _ | Int _ | Int64 _
        | FileIn _ | FileOut _
        | BufferIn _ | Key _ | Pointer _ -> ()
        | StringList n | DeviceList n -> pr "      free (%s);\n" n
      ) args;

      (* Check return value for errors and return it if necessary. *)
      (match ret with
       | RErr ->
           pr "      if (r == -1)\n";
           pr "        croak (\"%%s\", guestfs_last_error (g));\n";
       | RInt n
       | RBool n ->
           pr "      if (r == -1)\n";
           pr "        croak (\"%%s\", guestfs_last_error (g));\n";
           pr "      RETVAL = newSViv (r);\n";
           pr " OUTPUT:\n";
           pr "      RETVAL\n"
       | RInt64 n ->
           pr "      if (r == -1)\n";
           pr "        croak (\"%%s\", guestfs_last_error (g));\n";
           pr "      RETVAL = my_newSVll (r);\n";
           pr " OUTPUT:\n";
           pr "      RETVAL\n"
       | RConstString n ->
           pr "      if (r == NULL)\n";
           pr "        croak (\"%%s\", guestfs_last_error (g));\n";
           pr "      RETVAL = newSVpv (r, 0);\n";
           pr " OUTPUT:\n";
           pr "      RETVAL\n"
       | RConstOptString n ->
           pr "      if (r == NULL)\n";
           pr "        RETVAL = &PL_sv_undef;\n";
           pr "      else\n";
           pr "        RETVAL = newSVpv (r, 0);\n";
           pr " OUTPUT:\n";
           pr "      RETVAL\n"
       | RString n ->
           pr "      if (r == NULL)\n";
           pr "        croak (\"%%s\", guestfs_last_error (g));\n";
           pr "      RETVAL = newSVpv (r, 0);\n";
           pr "      free (r);\n";
           pr " OUTPUT:\n";
           pr "      RETVAL\n"
       | RStringList n | RHashtable n ->
           pr "      if (r == NULL)\n";
           pr "        croak (\"%%s\", guestfs_last_error (g));\n";
           pr "      for (n = 0; r[n] != NULL; ++n) /**/;\n";
           pr "      EXTEND (SP, n);\n";
           pr "      for (i = 0; i < n; ++i) {\n";
           pr "        PUSHs (sv_2mortal (newSVpv (r[i], 0)));\n";
           pr "        free (r[i]);\n";
           pr "      }\n";
           pr "      free (r);\n";
       | RStruct (n, typ) ->
           let cols = cols_of_struct typ in
           generate_perl_struct_code typ cols name style n
       | RStructList (n, typ) ->
           let cols = cols_of_struct typ in
           generate_perl_struct_list_code typ cols name style n
       | RBufferOut n ->
           pr "      if (r == NULL)\n";
           pr "        croak (\"%%s\", guestfs_last_error (g));\n";
           pr "      RETVAL = newSVpvn (r, size);\n";
           pr "      free (r);\n";
           pr " OUTPUT:\n";
           pr "      RETVAL\n"
      );

      pr "\n"
  ) all_functions

and generate_perl_struct_list_code typ cols name style n =
  pr "      if (r == NULL)\n";
  pr "        croak (\"%%s\", guestfs_last_error (g));\n";
  pr "      EXTEND (SP, r->len);\n";
  pr "      for (i = 0; i < r->len; ++i) {\n";
  pr "        hv = newHV ();\n";
  List.iter (
    function
    | name, FString ->
        pr "        (void) hv_store (hv, \"%s\", %d, newSVpv (r->val[i].%s, 0), 0);\n"
          name (String.length name) name
    | name, FUUID ->
        pr "        (void) hv_store (hv, \"%s\", %d, newSVpv (r->val[i].%s, 32), 0);\n"
          name (String.length name) name
    | name, FBuffer ->
        pr "        (void) hv_store (hv, \"%s\", %d, newSVpvn (r->val[i].%s, r->val[i].%s_len), 0);\n"
          name (String.length name) name name
    | name, (FBytes|FUInt64) ->
        pr "        (void) hv_store (hv, \"%s\", %d, my_newSVull (r->val[i].%s), 0);\n"
          name (String.length name) name
    | name, FInt64 ->
        pr "        (void) hv_store (hv, \"%s\", %d, my_newSVll (r->val[i].%s), 0);\n"
          name (String.length name) name
    | name, (FInt32|FUInt32) ->
        pr "        (void) hv_store (hv, \"%s\", %d, newSVnv (r->val[i].%s), 0);\n"
          name (String.length name) name
    | name, FChar ->
        pr "        (void) hv_store (hv, \"%s\", %d, newSVpv (&r->val[i].%s, 1), 0);\n"
          name (String.length name) name
    | name, FOptPercent ->
        pr "        (void) hv_store (hv, \"%s\", %d, newSVnv (r->val[i].%s), 0);\n"
          name (String.length name) name
  ) cols;
  pr "        PUSHs (sv_2mortal (newRV ((SV *) hv)));\n";
  pr "      }\n";
  pr "      guestfs_free_%s_list (r);\n" typ

and generate_perl_struct_code typ cols name style n =
  pr "      if (r == NULL)\n";
  pr "        croak (\"%%s\", guestfs_last_error (g));\n";
  pr "      EXTEND (SP, 2 * %d);\n" (List.length cols);
  List.iter (
    fun ((name, _) as col) ->
      pr "      PUSHs (sv_2mortal (newSVpv (\"%s\", 0)));\n" name;

      match col with
      | name, FString ->
          pr "      PUSHs (sv_2mortal (newSVpv (r->%s, 0)));\n"
            name
      | name, FBuffer ->
          pr "      PUSHs (sv_2mortal (newSVpvn (r->%s, r->%s_len)));\n"
            name name
      | name, FUUID ->
          pr "      PUSHs (sv_2mortal (newSVpv (r->%s, 32)));\n"
            name
      | name, (FBytes|FUInt64) ->
          pr "      PUSHs (sv_2mortal (my_newSVull (r->%s)));\n"
            name
      | name, FInt64 ->
          pr "      PUSHs (sv_2mortal (my_newSVll (r->%s)));\n"
            name
      | name, (FInt32|FUInt32) ->
          pr "      PUSHs (sv_2mortal (newSVnv (r->%s)));\n"
            name
      | name, FChar ->
          pr "      PUSHs (sv_2mortal (newSVpv (&r->%s, 1)));\n"
            name
      | name, FOptPercent ->
          pr "      PUSHs (sv_2mortal (newSVnv (r->%s)));\n"
            name
  ) cols;
  pr "      free (r);\n"

(* Generate Sys/Guestfs.pm. *)
and generate_perl_pm () =
  generate_header HashStyle LGPLv2plus;

  pr "\
=pod

=head1 NAME

Sys::Guestfs - Perl bindings for libguestfs

=head1 SYNOPSIS

 use Sys::Guestfs;

 my $g = Sys::Guestfs->new ();
 $g->add_drive_opts ('guest.img', format => 'raw');
 $g->launch ();
 $g->mount_options ('', '/dev/sda1', '/');
 $g->touch ('/hello');
 $g->shutdown ();
 $g->close ();

=head1 DESCRIPTION

The C<Sys::Guestfs> module provides a Perl XS binding to the
libguestfs API for examining and modifying virtual machine
disk images.

Amongst the things this is good for: making batch configuration
changes to guests, getting disk used/free statistics (see also:
virt-df), migrating between virtualization systems (see also:
virt-p2v), performing partial backups, performing partial guest
clones, cloning guests and changing registry/UUID/hostname info, and
much else besides.

Libguestfs uses Linux kernel and qemu code, and can access any type of
guest filesystem that Linux and qemu can, including but not limited
to: ext2/3/4, btrfs, FAT and NTFS, LVM, many different disk partition
schemes, qcow, qcow2, vmdk.

Libguestfs provides ways to enumerate guest storage (eg. partitions,
LVs, what filesystem is in each LV, etc.).  It can also run commands
in the context of the guest.  Also you can access filesystems over
FUSE.

See also L<Sys::Guestfs::Lib(3)> for a set of useful library
functions for using libguestfs from Perl, including integration
with libvirt.

=head1 ERRORS

All errors turn into calls to C<croak> (see L<Carp(3)>).

The error string from libguestfs is directly available from
C<$@>.  Use the C<last_errno> method if you want to get the errno.

=head1 METHODS

=over 4

=cut

package Sys::Guestfs;

use strict;
use warnings;

# This version number changes whenever a new function
# is added to the libguestfs API.  It is not directly
# related to the libguestfs version number.
use vars qw($VERSION);
$VERSION = '0.%d';

require XSLoader;
XSLoader::load ('Sys::Guestfs');

" max_proc_nr;

  (* Methods. *)
  pr "\
=item $g = Sys::Guestfs->new ();

Create a new guestfs handle.

=cut

sub new {
  my $proto = shift;
  my $class = ref ($proto) || $proto;

  my $g = Sys::Guestfs::_create ();
  my $self = { _g => $g };
  bless $self, $class;
  return $self;
}

=item $g->close ();

Explicitly close the guestfs handle.

B<Note:> You should not usually call this function.  The handle will
be closed implicitly when its reference count goes to zero (eg.
when it goes out of scope or the program ends).  This call is
only required in some exceptional cases, such as where the program
may contain cached references to the handle 'somewhere' and you
really have to have the close happen right away.  After calling
C<close> the program must not call any method (including C<close>)
on the handle (but the implicit call to C<DESTROY> that happens
when the final reference is cleaned up is OK).

";

  List.iter (
    fun (name, bitmask) ->
      pr "=item $Sys::Guestfs::EVENT_%s\n" (String.uppercase name);
      pr "\n";
      pr "See L<guestfs(3)/GUESTFS_EVENT_%s>.\n"
        (String.uppercase name);
      pr "\n";
      pr "=cut\n";
      pr "\n";
      pr "our $EVENT_%s = 0x%x;\n" (String.uppercase name) bitmask;
      pr "\n"
  ) events;

  pr "\
=item $event_handle = $g->set_event_callback (\\&cb, $event_bitmask);

Register C<cb> as a callback function for all of the events
in C<$event_bitmask> (one or more C<$Sys::Guestfs::EVENT_*> flags
logically or'd together).

This function returns an event handle which
can be used to delete the callback using C<delete_event_callback>.

The callback function receives 4 parameters:

 &cb ($event, $event_handle, $buf, $array)

=over 4

=item $event

The event which happened (equal to one of C<$Sys::Guestfs::EVENT_*>).

=item $event_handle

The event handle.

=item $buf

For some event types, this is a message buffer (ie. a string).

=item $array

For some event types (notably progress events), this is
an array of integers.

=back

You should carefully read the documentation for
L<guestfs(3)/guestfs_set_event_callback> before using
this function.

=item $g->delete_event_callback ($event_handle);

This removes the callback which was previously registered using
C<set_event_callback>.

=item $errnum = $g->last_errno ();

This returns the last error number (errno) that happened on the
handle C<$g>.

If successful, an errno integer not equal to zero is returned.

If no error number is available, this returns 0.
See L<guestfs(3)/guestfs_last_errno> for more details of why
this can happen.

You can use the standard Perl module L<Errno(3)> to compare
the numeric error returned from this call with symbolic
errnos:

 $g->mkdir (\"/foo\");
 if ($g->last_errno() == Errno::EEXIST()) {
   # mkdir failed because the directory exists already.
 }

=item $g->user_cancel ();

Cancel current transfer.  This is safe to call from Perl signal
handlers and threads.

=cut

";

  (* Actions.  We only need to print documentation for these as
   * they are pulled in from the XS code automatically.
   *)
  List.iter (
    fun (name, style, _, flags, _, _, longdesc) ->
      if not (List.mem NotInDocs flags) then (
        let longdesc = replace_str longdesc "C<guestfs_" "C<$g-E<gt>" in
        pr "=item ";
        generate_perl_prototype name style;
        pr "\n\n";
        pr "%s\n\n" longdesc;
        if List.mem ProtocolLimitWarning flags then
          pr "%s\n\n" protocol_limit_warning;
        match deprecation_notice flags with
        | None -> ()
        | Some txt -> pr "%s\n\n" txt
      )
  ) all_functions_sorted;

  pr "=cut\n\n";

  (* Introspection hash. *)
  pr "use vars qw(%%guestfs_introspection);\n";
  pr "%%guestfs_introspection = (\n";
  List.iter (
    fun (name, (ret, args, optargs), _, _, _, shortdesc, _) ->
      pr "  \"%s\" => {\n" name;
      pr "    ret => ";
      (match ret with
       | RErr -> pr "'void'"
       | RInt _ -> pr "'int'"
       | RBool _ -> pr "'bool'"
       | RInt64 _ -> pr "'int64'"
       | RConstString _ -> pr "'const string'"
       | RConstOptString _ -> pr "'const nullable string'"
       | RString _ -> pr "'string'"
       | RStringList _ -> pr "'string list'"
       | RHashtable _ -> pr "'hash'"
       | RStruct (_, typ) -> pr "'struct %s'" typ
       | RStructList (_, typ) -> pr "'struct %s list'" typ
       | RBufferOut _ -> pr "'buffer'"
      );
      pr ",\n";
      let pr_type i = function
        | Pathname n -> pr "[ '%s', 'string(path)', %d ]" n i
        | Device n -> pr "[ '%s', 'string(device)', %d ]" n i
        | Dev_or_Path n -> pr "[ '%s', 'string(dev_or_path)', %d ]" n i
        | String n -> pr "[ '%s', 'string', %d ]" n i
        | FileIn n -> pr "[ '%s', 'string(filename)', %d ]" n i
        | FileOut n -> pr "[ '%s', 'string(filename)', %d ]" n i
        | Key n -> pr "[ '%s', 'string(key)', %d ]" n i
        | BufferIn n -> pr "[ '%s', 'buffer', %d ]" n i
        | OptString n -> pr "[ '%s', 'nullable string', %d ]" n i
        | StringList n -> pr "[ '%s', 'string list', %d ]" n i
        | DeviceList n -> pr "[ '%s', 'string(device) list', %d ]" n i
        | Bool n -> pr "[ '%s', 'bool', %d ]" n i
        | Int n -> pr "[ '%s', 'int', %d ]" n i
        | Int64 n -> pr "[ '%s', 'int64', %d ]" n i
        | Pointer (t, n) -> pr "[ '%s', 'pointer(%s)', %d ]" n t i
      in
      pr "    args => [\n";
      iteri (fun i arg ->
        pr "      ";
        pr_type i arg;
        pr ",\n"
      ) args;
      pr "    ],\n";
      if optargs <> [] then (
        pr "    optargs => {\n";
        iteri (fun i arg ->
          pr "      %s => " (name_of_argt arg);
          pr_type i arg;
          pr ",\n"
        ) (args_of_optargs optargs);
        pr "    },\n";
      );
      pr "    name => \"%s\",\n" name;
      pr "    description => %S,\n" shortdesc;
      pr "  },\n";
  ) all_functions_sorted;
  pr ");\n\n";

  (* End of file. *)
  pr "\
1;

=back

=head1 AVAILABILITY

From time to time we add new libguestfs APIs.  Also some libguestfs
APIs won't be available in all builds of libguestfs (the Fedora
build is full-featured, but other builds may disable features).
How do you test whether the APIs that your Perl program needs are
available in the version of C<Sys::Guestfs> that you are using?

To test if a particular function is available in the C<Sys::Guestfs>
class, use the ordinary Perl UNIVERSAL method C<can(METHOD)>
(see L<perlobj(1)>).  For example:

 use Sys::Guestfs;
 if (defined (Sys::Guestfs->can (\"set_verbose\"))) {
   print \"\\$g->set_verbose is available\\n\";
 }

Perl does not offer a way to list the arguments of a method, and
from time to time we may add extra arguments to calls that take
optional arguments.  For this reason, we provide a global hash
variable C<%%guestfs_introspection> which contains the arguments
and their types for each libguestfs method.  The keys of this
hash are the method names, and the values are an hashref
containing useful introspection information about the method
(further fields may be added to this in future).

 use Sys::Guestfs;
 $Sys::Guestfs::guestfs_introspection{mkfs_opts}
 => {
    ret => 'void',                    # return type
    args => [                         # required arguments
      [ 'fstype', 'string', 0 ],
      [ 'device', 'string(device)', 1 ],
    ],
    optargs => {                      # optional arguments
      blocksize => [ 'blocksize', 'int', 0 ],
      features => [ 'features', 'string', 1 ],
      inode => [ 'inode', 'int', 2 ],
      sectorsize => [ 'sectorsize', 'int', 3 ],
    },
    name => \"mkfs_opts\",
    description => \"make a filesystem\",
  }

To test if particular features are supported by the current
build, use the L</available> method like the example below.  Note
that the appliance must be launched first.

 $g->available ( [\"augeas\"] );

Since the L</available> method croaks if the feature is not supported,
you might also want to wrap this in an eval and return a boolean.
In fact this has already been done for you: use
L<Sys::Guestfs::Lib(3)/feature_available>.

For further discussion on this topic, refer to
L<guestfs(3)/AVAILABILITY>.

=head1 STORING DATA IN THE HANDLE

The handle returned from L</new> is a hash reference.  The hash
normally contains a single element:

 {
   _g => [private data used by libguestfs]
 }

Callers can add other elements to this hash to store data for their own
purposes.  The data lasts for the lifetime of the handle.

Any fields whose names begin with an underscore are reserved
for private use by libguestfs.  We may add more in future.

It is recommended that callers prefix the name of their field(s)
with some unique string, to avoid conflicts with other users.

=head1 COPYRIGHT

Copyright (C) %s Red Hat Inc.

=head1 LICENSE

Please see the file COPYING.LIB for the full license.

=head1 SEE ALSO

L<guestfs(3)>,
L<guestfish(1)>,
L<http://libguestfs.org>,
L<Sys::Guestfs::Lib(3)>.

=cut
" copyright_years

and generate_perl_prototype name (ret, args, optargs) =
  (match ret with
   | RErr -> ()
   | RBool n
   | RInt n
   | RInt64 n
   | RConstString n
   | RConstOptString n
   | RString n
   | RBufferOut n -> pr "$%s = " n
   | RStruct (n,_)
   | RHashtable n -> pr "%%%s = " n
   | RStringList n
   | RStructList (n,_) -> pr "@%s = " n
  );
  pr "$g->%s (" name;
  let comma = ref false in
  List.iter (
    fun arg ->
      if !comma then pr ", ";
      comma := true;
      match arg with
      | Pathname n | Device n | Dev_or_Path n | String n
      | OptString n | Bool n | Int n | Int64 n | FileIn n | FileOut n
      | BufferIn n | Key n | Pointer (_, n) ->
          pr "$%s" n
      | StringList n | DeviceList n ->
          pr "\\@%s" n
  ) args;
  List.iter (
    fun arg ->
      if !comma then pr " [, " else pr "[";
      comma := true;
      let n = name_of_optargt arg in
      pr "%s => $%s]" n n
  ) optargs;
  pr ");"
