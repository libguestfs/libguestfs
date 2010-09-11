(* libguestfs
 * Copyright (C) 2009-2010 Red Hat Inc.
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

(* Generate Perl xs code, a sort of crazy variation of C with macros. *)
let rec generate_perl_xs () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include \"EXTERN.h\"
#include \"perl.h\"
#include \"XSUB.h\"

#include <guestfs.h>

#ifndef PRId64
#define PRId64 \"lld\"
#endif

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

#ifndef PRIu64
#define PRIu64 \"llu\"
#endif

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

#define PROGRESS_KEY \"_perl_progress_cb\"

static void
_clear_progress_callback (guestfs_h *g)
{
  guestfs_set_progress_callback (g, NULL, NULL);
  SV *cb = guestfs_get_private (g, PROGRESS_KEY);
  if (cb) {
    guestfs_set_private (g, PROGRESS_KEY, NULL);
    SvREFCNT_dec (cb);
  }
}

/* http://www.perlmonks.org/?node=338857 */
static void
_progress_callback (guestfs_h *g, void *cb,
                    int proc_nr, int serial, uint64_t position, uint64_t total)
{
  dSP;
  ENTER;
  SAVETMPS;
  PUSHMARK (SP);
  XPUSHs (sv_2mortal (newSViv (proc_nr)));
  XPUSHs (sv_2mortal (newSViv (serial)));
  XPUSHs (sv_2mortal (my_newSVull (position)));
  XPUSHs (sv_2mortal (my_newSVull (total)));
  PUTBACK;
  call_sv ((SV *) cb, G_VOID | G_DISCARD | G_EVAL);
  FREETMPS;
  LEAVE;
}

static void
_close_handle (guestfs_h *g)
{
  assert (g != NULL);
  _clear_progress_callback (g);
  guestfs_close (g);
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

void
set_progress_callback (g, cb)
      guestfs_h *g;
      SV *cb;
 PPCODE:
      _clear_progress_callback (g);
      SvREFCNT_inc (cb);
      guestfs_set_private (g, PROGRESS_KEY, cb);
      guestfs_set_progress_callback (g, _progress_callback, cb);

void
clear_progress_callback (g)
      guestfs_h *g;
 PPCODE:
      _clear_progress_callback (g);

";

  List.iter (
    fun (name, style, _, _, _, _, _) ->
      (match fst style with
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
      ) (snd style);
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
      ) (snd style);

      let do_cleanups () =
        List.iter (
          function
          | Pathname _ | Device _ | Dev_or_Path _ | String _ | OptString _
          | Bool _ | Int _ | Int64 _
          | FileIn _ | FileOut _
          | BufferIn _ | Key _ -> ()
          | StringList n | DeviceList n -> pr "      free (%s);\n" n
        ) (snd style)
      in

      (* Code. *)
      (match fst style with
       | RErr ->
           pr "PREINIT:\n";
           pr "      int r;\n";
           pr " PPCODE:\n";
           pr "      r = guestfs_%s " name;
           generate_c_call_args ~handle:"g" style;
           pr ";\n";
           do_cleanups ();
           pr "      if (r == -1)\n";
           pr "        croak (\"%%s\", guestfs_last_error (g));\n";
       | RInt n
       | RBool n ->
           pr "PREINIT:\n";
           pr "      int %s;\n" n;
           pr "   CODE:\n";
           pr "      %s = guestfs_%s " n name;
           generate_c_call_args ~handle:"g" style;
           pr ";\n";
           do_cleanups ();
           pr "      if (%s == -1)\n" n;
           pr "        croak (\"%%s\", guestfs_last_error (g));\n";
           pr "      RETVAL = newSViv (%s);\n" n;
           pr " OUTPUT:\n";
           pr "      RETVAL\n"
       | RInt64 n ->
           pr "PREINIT:\n";
           pr "      int64_t %s;\n" n;
           pr "   CODE:\n";
           pr "      %s = guestfs_%s " n name;
           generate_c_call_args ~handle:"g" style;
           pr ";\n";
           do_cleanups ();
           pr "      if (%s == -1)\n" n;
           pr "        croak (\"%%s\", guestfs_last_error (g));\n";
           pr "      RETVAL = my_newSVll (%s);\n" n;
           pr " OUTPUT:\n";
           pr "      RETVAL\n"
       | RConstString n ->
           pr "PREINIT:\n";
           pr "      const char *%s;\n" n;
           pr "   CODE:\n";
           pr "      %s = guestfs_%s " n name;
           generate_c_call_args ~handle:"g" style;
           pr ";\n";
           do_cleanups ();
           pr "      if (%s == NULL)\n" n;
           pr "        croak (\"%%s\", guestfs_last_error (g));\n";
           pr "      RETVAL = newSVpv (%s, 0);\n" n;
           pr " OUTPUT:\n";
           pr "      RETVAL\n"
       | RConstOptString n ->
           pr "PREINIT:\n";
           pr "      const char *%s;\n" n;
           pr "   CODE:\n";
           pr "      %s = guestfs_%s " n name;
           generate_c_call_args ~handle:"g" style;
           pr ";\n";
           do_cleanups ();
           pr "      if (%s == NULL)\n" n;
           pr "        RETVAL = &PL_sv_undef;\n";
           pr "      else\n";
           pr "        RETVAL = newSVpv (%s, 0);\n" n;
           pr " OUTPUT:\n";
           pr "      RETVAL\n"
       | RString n ->
           pr "PREINIT:\n";
           pr "      char *%s;\n" n;
           pr "   CODE:\n";
           pr "      %s = guestfs_%s " n name;
           generate_c_call_args ~handle:"g" style;
           pr ";\n";
           do_cleanups ();
           pr "      if (%s == NULL)\n" n;
           pr "        croak (\"%%s\", guestfs_last_error (g));\n";
           pr "      RETVAL = newSVpv (%s, 0);\n" n;
           pr "      free (%s);\n" n;
           pr " OUTPUT:\n";
           pr "      RETVAL\n"
       | RStringList n | RHashtable n ->
           pr "PREINIT:\n";
           pr "      char **%s;\n" n;
           pr "      size_t i, n;\n";
           pr " PPCODE:\n";
           pr "      %s = guestfs_%s " n name;
           generate_c_call_args ~handle:"g" style;
           pr ";\n";
           do_cleanups ();
           pr "      if (%s == NULL)\n" n;
           pr "        croak (\"%%s\", guestfs_last_error (g));\n";
           pr "      for (n = 0; %s[n] != NULL; ++n) /**/;\n" n;
           pr "      EXTEND (SP, n);\n";
           pr "      for (i = 0; i < n; ++i) {\n";
           pr "        PUSHs (sv_2mortal (newSVpv (%s[i], 0)));\n" n;
           pr "        free (%s[i]);\n" n;
           pr "      }\n";
           pr "      free (%s);\n" n;
       | RStruct (n, typ) ->
           let cols = cols_of_struct typ in
           generate_perl_struct_code typ cols name style n do_cleanups
       | RStructList (n, typ) ->
           let cols = cols_of_struct typ in
           generate_perl_struct_list_code typ cols name style n do_cleanups
       | RBufferOut n ->
           pr "PREINIT:\n";
           pr "      char *%s;\n" n;
           pr "      size_t size;\n";
           pr "   CODE:\n";
           pr "      %s = guestfs_%s " n name;
           generate_c_call_args ~handle:"g" style;
           pr ";\n";
           do_cleanups ();
           pr "      if (%s == NULL)\n" n;
           pr "        croak (\"%%s\", guestfs_last_error (g));\n";
           pr "      RETVAL = newSVpvn (%s, size);\n" n;
           pr "      free (%s);\n" n;
           pr " OUTPUT:\n";
           pr "      RETVAL\n"
      );

      pr "\n"
  ) all_functions

and generate_perl_struct_list_code typ cols name style n do_cleanups =
  pr "PREINIT:\n";
  pr "      struct guestfs_%s_list *%s;\n" typ n;
  pr "      size_t i;\n";
  pr "      HV *hv;\n";
  pr " PPCODE:\n";
  pr "      %s = guestfs_%s " n name;
  generate_c_call_args ~handle:"g" style;
  pr ";\n";
  do_cleanups ();
  pr "      if (%s == NULL)\n" n;
  pr "        croak (\"%%s\", guestfs_last_error (g));\n";
  pr "      EXTEND (SP, %s->len);\n" n;
  pr "      for (i = 0; i < %s->len; ++i) {\n" n;
  pr "        hv = newHV ();\n";
  List.iter (
    function
    | name, FString ->
        pr "        (void) hv_store (hv, \"%s\", %d, newSVpv (%s->val[i].%s, 0), 0);\n"
          name (String.length name) n name
    | name, FUUID ->
        pr "        (void) hv_store (hv, \"%s\", %d, newSVpv (%s->val[i].%s, 32), 0);\n"
          name (String.length name) n name
    | name, FBuffer ->
        pr "        (void) hv_store (hv, \"%s\", %d, newSVpvn (%s->val[i].%s, %s->val[i].%s_len), 0);\n"
          name (String.length name) n name n name
    | name, (FBytes|FUInt64) ->
        pr "        (void) hv_store (hv, \"%s\", %d, my_newSVull (%s->val[i].%s), 0);\n"
          name (String.length name) n name
    | name, FInt64 ->
        pr "        (void) hv_store (hv, \"%s\", %d, my_newSVll (%s->val[i].%s), 0);\n"
          name (String.length name) n name
    | name, (FInt32|FUInt32) ->
        pr "        (void) hv_store (hv, \"%s\", %d, newSVnv (%s->val[i].%s), 0);\n"
          name (String.length name) n name
    | name, FChar ->
        pr "        (void) hv_store (hv, \"%s\", %d, newSVpv (&%s->val[i].%s, 1), 0);\n"
          name (String.length name) n name
    | name, FOptPercent ->
        pr "        (void) hv_store (hv, \"%s\", %d, newSVnv (%s->val[i].%s), 0);\n"
          name (String.length name) n name
  ) cols;
  pr "        PUSHs (sv_2mortal (newRV ((SV *) hv)));\n";
  pr "      }\n";
  pr "      guestfs_free_%s_list (%s);\n" typ n

and generate_perl_struct_code typ cols name style n do_cleanups =
  pr "PREINIT:\n";
  pr "      struct guestfs_%s *%s;\n" typ n;
  pr " PPCODE:\n";
  pr "      %s = guestfs_%s " n name;
  generate_c_call_args ~handle:"g" style;
  pr ";\n";
  do_cleanups ();
  pr "      if (%s == NULL)\n" n;
  pr "        croak (\"%%s\", guestfs_last_error (g));\n";
  pr "      EXTEND (SP, 2 * %d);\n" (List.length cols);
  List.iter (
    fun ((name, _) as col) ->
      pr "      PUSHs (sv_2mortal (newSVpv (\"%s\", 0)));\n" name;

      match col with
      | name, FString ->
          pr "      PUSHs (sv_2mortal (newSVpv (%s->%s, 0)));\n"
            n name
      | name, FBuffer ->
          pr "      PUSHs (sv_2mortal (newSVpvn (%s->%s, %s->%s_len)));\n"
            n name n name
      | name, FUUID ->
          pr "      PUSHs (sv_2mortal (newSVpv (%s->%s, 32)));\n"
            n name
      | name, (FBytes|FUInt64) ->
          pr "      PUSHs (sv_2mortal (my_newSVull (%s->%s)));\n"
            n name
      | name, FInt64 ->
          pr "      PUSHs (sv_2mortal (my_newSVll (%s->%s)));\n"
            n name
      | name, (FInt32|FUInt32) ->
          pr "      PUSHs (sv_2mortal (newSVnv (%s->%s)));\n"
            n name
      | name, FChar ->
          pr "      PUSHs (sv_2mortal (newSVpv (&%s->%s, 1)));\n"
            n name
      | name, FOptPercent ->
          pr "      PUSHs (sv_2mortal (newSVnv (%s->%s)));\n"
            n name
  ) cols;
  pr "      free (%s);\n" n

(* Generate Sys/Guestfs.pm. *)
and generate_perl_pm () =
  generate_header HashStyle LGPLv2plus;

  pr "\
=pod

=head1 NAME

Sys::Guestfs - Perl bindings for libguestfs

=head1 SYNOPSIS

 use Sys::Guestfs;

 my $h = Sys::Guestfs->new ();
 $h->add_drive ('guest.img');
 $h->launch ();
 $h->mount ('/dev/sda1', '/');
 $h->touch ('/hello');
 $h->sync ();

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

=item $h = Sys::Guestfs->new ();

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

=item $h->close ();

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

=item $h->set_progress_callback (\\&cb);

Set the progress notification callback for this handle
to the Perl closure C<cb>.

C<cb> will be called whenever a long-running operation
generates a progress notification message.  The 4 parameters
to the function are: C<proc_nr>, C<serial>, C<position>
and C<total>.

You should carefully read the documentation for
L<guestfs(3)/guestfs_set_progress_callback> before using
this function.

=item $h->clear_progress_callback ();

This removes any progress callback function associated with
the handle.

=cut

" max_proc_nr;

  (* Actions.  We only need to print documentation for these as
   * they are pulled in from the XS code automatically.
   *)
  List.iter (
    fun (name, style, _, flags, _, _, longdesc) ->
      if not (List.mem NotInDocs flags) then (
        let longdesc = replace_str longdesc "C<guestfs_" "C<$h-E<gt>" in
        pr "=item ";
        generate_perl_prototype name style;
        pr "\n\n";
        pr "%s\n\n" longdesc;
        if List.mem ProtocolLimitWarning flags then
          pr "%s\n\n" protocol_limit_warning;
        if List.mem DangerWillRobinson flags then
          pr "%s\n\n" danger_will_robinson;
        match deprecation_notice flags with
        | None -> ()
        | Some txt -> pr "%s\n\n" txt
      )
  ) all_functions_sorted;

  (* End of file. *)
  pr "\
=cut

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
   print \"\\$h->set_verbose is available\\n\";
 }

To test if particular features are supported by the current
build, use the L</available> method like the example below.  Note
that the appliance must be launched first.

 $h->available ( [\"augeas\"] );

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

and generate_perl_prototype name style =
  (match fst style with
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
  pr "$h->%s (" name;
  let comma = ref false in
  List.iter (
    fun arg ->
      if !comma then pr ", ";
      comma := true;
      match arg with
      | Pathname n | Device n | Dev_or_Path n | String n
      | OptString n | Bool n | Int n | Int64 n | FileIn n | FileOut n
      | BufferIn n | Key n ->
          pr "$%s" n
      | StringList n | DeviceList n ->
          pr "\\@%s" n
  ) (snd style);
  pr ");"
