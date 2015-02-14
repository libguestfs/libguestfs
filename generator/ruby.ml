(* libguestfs
 * Copyright (C) 2009-2014 Red Hat Inc.
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

open Types
open Utils
open Pr
open Docstrings
open Optgroups
open Actions
open Structs
open C
open Events

(* Generate ruby bindings. *)
let rec generate_ruby_c () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <assert.h>

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored \"-Wstrict-prototypes\"
#include <ruby.h>
#pragma GCC diagnostic pop

/* ruby/defines.h defines '_'. */
#ifdef _
#undef _
#endif

#include \"guestfs.h\"
#include \"guestfs-internal-frontend.h\"

#include \"extconf.h\"

/* Ruby has a mark-sweep garbage collector and performs imprecise
 * scanning of the stack to look for pointers.  Some implications
 * of this:
 * (1) Any VALUE stored in a stack location must be marked as
 *     volatile so that the compiler doesn't put it in a register.
 * (2) Anything at all on the stack that \"looks like\" a Ruby
 *     pointer could be followed, eg. buffers of random data.
 *     (See: https://bugzilla.redhat.com/show_bug.cgi?id=843188#c6)
 * We fix (1) by marking everything possible as volatile.
 */

/* For Ruby < 1.9 */
#ifndef RARRAY_LEN
#define RARRAY_LEN(r) (RARRAY((r))->len)
#endif

/* For Ruby < 1.8 */
#ifndef RSTRING_LEN
#define RSTRING_LEN(r) (RSTRING((r))->len)
#endif

#ifndef RSTRING_PTR
#define RSTRING_PTR(r) (RSTRING((r))->ptr)
#endif

/* For RHEL 5 (Ruby 1.8.5) */
#ifndef HAVE_RB_HASH_LOOKUP
VALUE
rb_hash_lookup (VALUE hash, VALUE key)
{
  volatile VALUE val;

  if (!st_lookup (RHASH(hash)->tbl, key, &val))
    return Qnil;

  return val;
}
#endif /* !HAVE_RB_HASH_LOOKUP */

static VALUE m_guestfs;			/* guestfs module */
static VALUE c_guestfs;			/* guestfs_h handle */
static VALUE e_Error;			/* used for all errors */

static void ruby_event_callback_wrapper (guestfs_h *g, void *data, uint64_t event, int event_handle, int flags, const char *buf, size_t buf_len, const uint64_t *array, size_t array_len);
static VALUE ruby_event_callback_wrapper_wrapper (VALUE argv);
static VALUE ruby_event_callback_handle_exception (VALUE not_used, VALUE exn);
static VALUE **get_all_event_callbacks (guestfs_h *g, size_t *len_rtn);

static void
ruby_guestfs_free (void *gvp)
{
  guestfs_h *g = gvp;

  if (g) {
    /* As in the OCaml binding, there is a nasty, difficult to
     * solve case here where the user deletes events in one of
     * the callbacks that we are about to invoke, resulting in
     * a double-free.  XXX
     */
    size_t len, i;
    VALUE **roots = get_all_event_callbacks (g, &len);

    /* Close the handle: this could invoke callbacks from the list
     * above, which is why we don't want to delete them before
     * closing the handle.
     */
    guestfs_close (g);

    /* Now unregister the global roots. */
    for (i = 0; i < len; ++i) {
      rb_gc_unregister_address (roots[i]);
      free (roots[i]);
    }
    free (roots);
  }
}

/* This is the ruby internal alloc function for the class.  We do nothing
 * here except allocate an object containing a NULL guestfs handle.
 * Note we cannot call guestfs_create here because we need the extra
 * parameters, which ruby passes via the initialize method (see next
 * function).
 */
static VALUE
ruby_guestfs_alloc (VALUE klass)
{
  guestfs_h *g = NULL;

  /* Wrap it, and make sure the close function is called when the
   * handle goes away.
   */
  return Data_Wrap_Struct (c_guestfs, NULL, ruby_guestfs_free, g);
}

static unsigned
parse_flags (int argc, VALUE *argv)
{
  volatile VALUE optargsv;
  unsigned flags = 0;
  volatile VALUE v;

  optargsv = argc == 1 ? argv[0] : rb_hash_new ();
  Check_Type (optargsv, T_HASH);

  v = rb_hash_lookup (optargsv, ID2SYM (rb_intern (\"environment\")));
  if (v != Qnil && !RTEST (v))
    flags |= GUESTFS_CREATE_NO_ENVIRONMENT;
  v = rb_hash_lookup (optargsv, ID2SYM (rb_intern (\"close_on_exit\")));
  if (v != Qnil && !RTEST (v))
    flags |= GUESTFS_CREATE_NO_CLOSE_ON_EXIT;

  return flags;
}

/*
 * call-seq:
 *   Guestfs::Guestfs.new([{:environment => false, :close_on_exit => false}]) -> Guestfs::Guestfs
 *
 * Call
 * +guestfs_create_flags+[http://libguestfs.org/guestfs.3.html#guestfs_create_flags]
 * to create a new libguestfs handle.  The handle is represented in
 * Ruby as an instance of the Guestfs::Guestfs class.
 */
static VALUE
ruby_guestfs_initialize (int argc, VALUE *argv, VALUE m)
{
  guestfs_h *g;
  unsigned flags;

  if (argc > 1)
    rb_raise (rb_eArgError, \"expecting 0 or 1 arguments\");

  /* Should have been set to NULL by prior call to alloc function. */
  assert (DATA_PTR (m) == NULL);

  flags = parse_flags (argc, argv);

  g = guestfs_create_flags (flags);
  if (!g)
    rb_raise (e_Error, \"failed to create guestfs handle\");

  DATA_PTR (m) = g;

  /* Don't print error messages to stderr by default. */
  guestfs_set_error_handler (g, NULL, NULL);

  return m;
}

/* For backwards compatibility. */
static VALUE
ruby_guestfs_create (int argc, VALUE *argv, VALUE module)
{
  guestfs_h *g;
  unsigned flags;

  if (argc > 1)
    rb_raise (rb_eArgError, \"expecting 0 or 1 arguments\");

  flags = parse_flags (argc, argv);

  g = guestfs_create_flags (flags);
  if (!g)
    rb_raise (e_Error, \"failed to create guestfs handle\");

  /* Don't print error messages to stderr by default. */
  guestfs_set_error_handler (g, NULL, NULL);

  return Data_Wrap_Struct (c_guestfs, NULL, ruby_guestfs_free, g);
}

/*
 * call-seq:
 *   g.close() -> nil
 *
 * Call
 * +guestfs_close+[http://libguestfs.org/guestfs.3.html#guestfs_close]
 * to close the libguestfs handle.
 */
static VALUE
ruby_guestfs_close (VALUE gv)
{
  guestfs_h *g;
  Data_Get_Struct (gv, guestfs_h, g);

  /* Clear the data pointer first so there's no chance of a double
   * close if a close callback does something bad like calling exit.
   */
  DATA_PTR (gv) = NULL;
  ruby_guestfs_free (g);

  return Qnil;
}

/*
 * call-seq:
 *   g.set_event_callback(cb, event_bitmask) -> event_handle
 *
 * Call
 * +guestfs_set_event_callback+[http://libguestfs.org/guestfs.3.html#guestfs_set_event_callback]
 * to register an event callback.  This returns an event handle.
 */
static VALUE
ruby_set_event_callback (VALUE gv, VALUE cbv, VALUE event_bitmaskv)
{
  guestfs_h *g;
  uint64_t event_bitmask;
  int eh;
  VALUE *root;
  char key[64];

  Data_Get_Struct (gv, guestfs_h, g);

  event_bitmask = NUM2ULL (event_bitmaskv);

  root = guestfs_int_safe_malloc (g, sizeof *root);
  *root = cbv;

  eh = guestfs_set_event_callback (g, ruby_event_callback_wrapper,
                                   event_bitmask, 0, root);
  if (eh == -1) {
    free (root);
    rb_raise (e_Error, \"%%s\", guestfs_last_error (g));
  }

  rb_gc_register_address (root);

  snprintf (key, sizeof key, \"_ruby_event_%%d\", eh);
  guestfs_set_private (g, key, root);

  return INT2NUM (eh);
}

/*
 * call-seq:
 *   g.delete_event_callback(event_handle) -> nil
 *
 * Call
 * +guestfs_delete_event_callback+[http://libguestfs.org/guestfs.3.html#guestfs_delete_event_callback]
 * to delete an event callback.
 */
static VALUE
ruby_delete_event_callback (VALUE gv, VALUE event_handlev)
{
  guestfs_h *g;
  char key[64];
  int eh = NUM2INT (event_handlev);
  VALUE *root;

  Data_Get_Struct (gv, guestfs_h, g);

  snprintf (key, sizeof key, \"_ruby_event_%%d\", eh);

  root = guestfs_get_private (g, key);
  if (root) {
    rb_gc_unregister_address (root);
    free (root);
    guestfs_set_private (g, key, NULL);
    guestfs_delete_event_callback (g, eh);
  }

  return Qnil;
}

/*
 * call-seq:
 *   Guestfs::Guestfs.event_to_string(events) -> string
 *
 * Call
 * +guestfs_event_to_string+[http://libguestfs.org/guestfs.3.html#guestfs_event_to_string]
 * to convert an event or event bitmask into a printable string.
 */
static VALUE
ruby_event_to_string (VALUE modulev, VALUE eventsv)
{
  uint64_t events;
  char *str;

  events = NUM2ULL (eventsv);
  str = guestfs_event_to_string (events);
  if (str == NULL)
    rb_raise (e_Error, \"%%s\", strerror (errno));

  volatile VALUE rv = rb_str_new2 (str);
  free (str);

  return rv;
}

static void
ruby_event_callback_wrapper (guestfs_h *g,
                             void *data,
                             uint64_t event,
                             int event_handle,
                             int flags,
                             const char *buf, size_t buf_len,
                             const uint64_t *array, size_t array_len)
{
  size_t i;
  volatile VALUE eventv, event_handlev, bufv, arrayv;
  volatile VALUE argv[5];

  eventv = ULL2NUM (event);
  event_handlev = INT2NUM (event_handle);

  bufv = rb_str_new (buf, buf_len);

  arrayv = rb_ary_new2 (array_len);
  for (i = 0; i < array_len; ++i)
    rb_ary_push (arrayv, ULL2NUM (array[i]));

  /* This is a crap limitation of rb_rescue.
   * http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/~poffice/mail/ruby-talk/65698
   */
  argv[0] = * (VALUE *) data; /* function */
  argv[1] = eventv;
  argv[2] = event_handlev;
  argv[3] = bufv;
  argv[4] = arrayv;

  rb_rescue (ruby_event_callback_wrapper_wrapper, (VALUE) argv,
             ruby_event_callback_handle_exception, Qnil);
}

static VALUE
ruby_event_callback_wrapper_wrapper (VALUE argvv)
{
  VALUE *argv = (VALUE *) argvv;
  volatile VALUE fn, eventv, event_handlev, bufv, arrayv;

  fn = argv[0];

  /* Check the Ruby callback still exists.  For reasons which are not
   * fully understood, even though we registered this as a global root,
   * it is still possible for the callback to go away (fn value remains
   * but its type changes from T_DATA to T_NONE or T_ZOMBIE).
   * (RHBZ#733297, RHBZ#843188)
   */
  if (rb_type (fn) != T_NONE
#ifdef T_ZOMBIE
      && rb_type (fn) != T_ZOMBIE
#endif
      ) {
    eventv = argv[1];
    event_handlev = argv[2];
    bufv = argv[3];
    arrayv = argv[4];

    rb_funcall (fn, rb_intern (\"call\"), 4,
                eventv, event_handlev, bufv, arrayv);
  }

  return Qnil;
}

static VALUE
ruby_event_callback_handle_exception (VALUE not_used, VALUE exn)
{
  /* Callbacks aren't supposed to throw exceptions. */
  fprintf (stderr, \"libguestfs: exception in callback!\\n\");

  /* XXX We could print the exception, but it's very difficult from
   * a Ruby extension.
   */

  return Qnil;
}

static VALUE **
get_all_event_callbacks (guestfs_h *g, size_t *len_rtn)
{
  VALUE **r;
  size_t i;
  const char *key;
  VALUE *root;

  /* Count the length of the array that will be needed. */
  *len_rtn = 0;
  root = guestfs_first_private (g, &key);
  while (root != NULL) {
    if (strncmp (key, \"_ruby_event_\", strlen (\"_ruby_event_\")) == 0)
      (*len_rtn)++;
    root = guestfs_next_private (g, &key);
  }

  /* Copy them into the return array. */
  r = guestfs_int_safe_malloc (g, sizeof (VALUE *) * (*len_rtn));

  i = 0;
  root = guestfs_first_private (g, &key);
  while (root != NULL) {
    if (strncmp (key, \"_ruby_event_\", strlen (\"_ruby_event_\")) == 0) {
      r[i] = root;
      i++;
    }
    root = guestfs_next_private (g, &key);
  }

  return r;
}

";

  List.iter (
    fun f ->
      let ret, args, optargs = f.style in

      (* Generate rdoc. *)
      if is_documented f then (
        let doc = replace_str f.longdesc "C<guestfs_" "C<g." in
        let doc =
          if optargs <> [] then
            doc ^ "\n\nOptional arguments are supplied in the final hash parameter, which is a hash of the argument name to its value.  Pass an empty {} for no optional arguments."
          else doc in
        let doc =
          if f.protocol_limit_warning then
            doc ^ "\n\n" ^ protocol_limit_warning
          else doc in
        let doc =
          match deprecation_notice f with
          | None -> doc
          | Some txt -> doc ^ "\n\n" ^ txt in
        let doc = pod2text ~width:60 f.name doc in
        let doc = String.concat "\n * " doc in
        let doc = trim doc in

        (* Because Ruby documentation appears as C comments, we must
         * replace any instance of "/*".
         *)
        let doc = replace_str doc "/*" "/ *" in

        let args = List.map name_of_argt args in
        let args = if optargs <> [] then args @ ["{optargs...}"] else args in
        let args = String.concat ", " args in

        let ret =
          match ret with
          | RErr -> "nil"
          | RBool _ -> "[True|False]"
          | RInt _ -> "fixnum"
          | RInt64 _ -> "fixnum"
          | RConstString _ -> "string"
          | RConstOptString _ -> "string"
          | RString _ -> "string"
          | RBufferOut _ -> "string"
          | RStruct _
          | RHashtable _ -> "hash"
          | RStringList _
          | RStructList _ -> "list" in

        pr "\
/*
 * call-seq:
 *   g.%s(%s) -> %s
 *
 * %s
 *
 * %s
 *
 * (For the C API documentation for this function, see
 * +guestfs_%s+[http://libguestfs.org/guestfs.3.html#guestfs_%s]).
 */
" f.name args ret f.shortdesc doc f.name f.name
      ) else (
        pr "\
/*
 * call-seq:
 *   g.%s
 *
 * :nodoc:
 */
" f.name
      );

      (* Generate the function.  Prototype is completely different
       * depending on whether it's got optargs or not.
       *
       * See:
       * http://stackoverflow.com/questions/7626745/extending-ruby-in-c-how-to-specify-default-argument-values-to-function
       *)
      pr "static VALUE\n";
      pr "ruby_guestfs_%s (" f.name;
      if optargs = [] then (
        pr "VALUE gv";
        List.iter
          (fun arg -> pr ", VALUE %sv" (name_of_argt arg))
          args
      ) else
        pr "int argc, VALUE *argv, VALUE gv";
      pr ")\n";
      pr "{\n";
      pr "  guestfs_h *g;\n";
      pr "  Data_Get_Struct (gv, guestfs_h, g);\n";
      pr "  if (!g)\n";
      pr "    rb_raise (rb_eArgError, \"%%s: used handle after closing it\", \"%s\");\n"
        f.name;
      pr "\n";

      (* For optargs case, get the arg VALUEs into local variables.
       * Note for compatibility with old code we're still expecting
       * just a single optional hash parameter as the final element
       * containing all the optargs.
       *)
      if optargs <> [] then (
        let nr_args = List.length args in
        pr "  if (argc < %d || argc > %d)\n" nr_args (nr_args+1);
        pr "    rb_raise (rb_eArgError, \"expecting %d or %d arguments\");\n" nr_args (nr_args+1);
        pr "\n";
        iteri (
          fun i arg ->
            pr "  volatile VALUE %sv = argv[%d];\n" (name_of_argt arg) i
        ) args;
        pr "  volatile VALUE optargsv = argc > %d ? argv[%d] : rb_hash_new ();\n"
          nr_args nr_args;
        pr "\n"
      );

      List.iter (
        function
        | Pathname n | Device n | Mountable n
        | Dev_or_Path n | Mountable_or_Path n | String n | Key n
        | FileIn n | FileOut n | GUID n ->
          pr "  const char *%s = StringValueCStr (%sv);\n" n n;
        | BufferIn n ->
          pr "  Check_Type (%sv, T_STRING);\n" n;
          pr "  const char *%s = RSTRING_PTR (%sv);\n" n n;
          pr "  if (!%s)\n" n;
          pr "    rb_raise (rb_eTypeError, \"expected string for parameter %%s of %%s\",\n";
          pr "              \"%s\", \"%s\");\n" n f.name;
          pr "  size_t %s_size = RSTRING_LEN (%sv);\n" n n
        | OptString n ->
          pr "  const char *%s = !NIL_P (%sv) ? StringValueCStr (%sv) : NULL;\n" n n n
        | StringList n | DeviceList n ->
          pr "  char **%s;\n" n;
          pr "  Check_Type (%sv, T_ARRAY);\n" n;
          pr "  {\n";
          pr "    size_t i, len;\n";
          pr "    len = RARRAY_LEN (%sv);\n" n;
          pr "    %s = ALLOC_N (char *, len+1);\n"
            n;
          pr "    for (i = 0; i < len; ++i) {\n";
          pr "      volatile VALUE v = rb_ary_entry (%sv, i);\n" n;
          pr "      %s[i] = StringValueCStr (v);\n" n;
          pr "    }\n";
          pr "    %s[len] = NULL;\n" n;
          pr "  }\n";
        | Bool n ->
          pr "  int %s = RTEST (%sv);\n" n n
        | Int n ->
          pr "  int %s = NUM2INT (%sv);\n" n n
        | Int64 n ->
          pr "  long long %s = NUM2LL (%sv);\n" n n
        | Pointer (t, n) ->
          pr "  %s %s = (%s) (intptr_t) NUM2LL (%sv);\n" t n t n
      ) args;
      pr "\n";

      (* Optional arguments are passed in a final hash parameter. *)
      if optargs <> [] then (
        pr "  Check_Type (optargsv, T_HASH);\n";
        pr "  struct %s optargs_s = { .bitmask = 0 };\n" f.c_function;
        pr "  struct %s *optargs = &optargs_s;\n" f.c_function;
        pr "  volatile VALUE v;\n";
        List.iter (
          fun argt ->
            let n = name_of_optargt argt in
            let uc_n = String.uppercase n in
            pr "  v = rb_hash_lookup (optargsv, ID2SYM (rb_intern (\"%s\")));\n" n;
            pr "  if (v != Qnil) {\n";
            (match argt with
             | OBool n ->
                 pr "    optargs_s.%s = RTEST (v);\n" n;
             | OInt n ->
                 pr "    optargs_s.%s = NUM2INT (v);\n" n;
             | OInt64 n ->
                 pr "    optargs_s.%s = NUM2LL (v);\n" n;
             | OString _ ->
                 pr "    optargs_s.%s = StringValueCStr (v);\n" n
             | OStringList _ ->
               pr "  Check_Type (v, T_ARRAY);\n";
               pr "  {\n";
               pr "    size_t i, len;\n";
               pr "    char **r;\n";
               pr "\n";
               pr "    len = RARRAY_LEN (v);\n";
               pr "    r = ALLOC_N (char *, len+1);\n";
               pr "    for (i = 0; i < len; ++i) {\n";
               pr "      volatile VALUE sv = rb_ary_entry (v, i);\n";
               pr "      r[i] = StringValueCStr (sv);\n";
               pr "    }\n";
               pr "    r[len] = NULL;\n";
               pr "    optargs_s.%s = r;\n" n;
               pr "  }\n"
            );
            pr "    optargs_s.bitmask |= %s_%s_BITMASK;\n" f.c_optarg_prefix uc_n;
            pr "  }\n";
        ) optargs;
        pr "\n";
      );

      (match ret with
       | RErr | RInt _ | RBool _ -> pr "  int r;\n"
       | RInt64 _ -> pr "  int64_t r;\n"
       | RConstString _ | RConstOptString _ ->
           pr "  const char *r;\n"
       | RString _ -> pr "  char *r;\n"
       | RStringList _ | RHashtable _ -> pr "  char **r;\n"
       | RStruct (_, typ) -> pr "  struct guestfs_%s *r;\n" typ
       | RStructList (_, typ) ->
           pr "  struct guestfs_%s_list *r;\n" typ
       | RBufferOut _ ->
           pr "  char *r;\n";
           pr "  size_t size;\n"
      );
      pr "\n";

      pr "  r = %s " f.c_function;
      generate_c_call_args ~handle:"g" f.style;
      pr ";\n";

      List.iter (
        function
        | Pathname _ | Device _ | Mountable _
        | Dev_or_Path _ | Mountable_or_Path _ | String _ | Key _
        | FileIn _ | FileOut _ | OptString _ | Bool _ | Int _ | Int64 _
        | BufferIn _ | Pointer _ | GUID _ -> ()
        | StringList n | DeviceList n ->
            pr "  free (%s);\n" n
      ) args;

      (match errcode_of_ret ret with
       | `CannotReturnError -> ()
       | `ErrorIsMinusOne ->
           pr "  if (r == -1)\n";
           pr "    rb_raise (e_Error, \"%%s\", guestfs_last_error (g));\n"
       | `ErrorIsNULL ->
           pr "  if (r == NULL)\n";
           pr "    rb_raise (e_Error, \"%%s\", guestfs_last_error (g));\n"
      );
      pr "\n";

      (match ret with
       | RErr ->
           pr "  return Qnil;\n"
       | RInt _ | RBool _ ->
           pr "  return INT2NUM (r);\n"
       | RInt64 _ ->
           pr "  return ULL2NUM (r);\n"
       | RConstString _ ->
           pr "  return rb_str_new2 (r);\n";
       | RConstOptString _ ->
           pr "  if (r)\n";
           pr "    return rb_str_new2 (r);\n";
           pr "  else\n";
           pr "    return Qnil;\n";
       | RString _ ->
           pr "  volatile VALUE rv = rb_str_new2 (r);\n";
           pr "  free (r);\n";
           pr "  return rv;\n";
       | RStringList _ ->
           pr "  size_t i, len = 0;\n";
           pr "  for (i = 0; r[i] != NULL; ++i) len++;\n";
           pr "  volatile VALUE rv = rb_ary_new2 (len);\n";
           pr "  for (i = 0; r[i] != NULL; ++i) {\n";
           pr "    rb_ary_push (rv, rb_str_new2 (r[i]));\n";
           pr "    free (r[i]);\n";
           pr "  }\n";
           pr "  free (r);\n";
           pr "  return rv;\n"
       | RStruct (_, typ) ->
           let cols = cols_of_struct typ in
           generate_ruby_struct_code typ cols
       | RStructList (_, typ) ->
           let cols = cols_of_struct typ in
           generate_ruby_struct_list_code typ cols
       | RHashtable _ ->
           pr "  volatile VALUE rv = rb_hash_new ();\n";
           pr "  size_t i;\n";
           pr "  for (i = 0; r[i] != NULL; i+=2) {\n";
           pr "    rb_hash_aset (rv, rb_str_new2 (r[i]), rb_str_new2 (r[i+1]));\n";
           pr "    free (r[i]);\n";
           pr "    free (r[i+1]);\n";
           pr "  }\n";
           pr "  free (r);\n";
           pr "  return rv;\n"
       | RBufferOut _ ->
           pr "  volatile VALUE rv = rb_str_new (r, size);\n";
           pr "  free (r);\n";
           pr "  return rv;\n";
      );

      pr "}\n";
      pr "\n"
  ) external_functions_sorted;

  pr "\
extern void Init__guestfs (void); /* keep GCC warnings happy */

/* Initialize the module. */
void
Init__guestfs (void)
{
  m_guestfs = rb_define_module (\"Guestfs\");
  c_guestfs = rb_define_class_under (m_guestfs, \"Guestfs\", rb_cObject);
  e_Error = rb_define_class_under (m_guestfs, \"Error\", rb_eStandardError);

#ifdef HAVE_RB_DEFINE_ALLOC_FUNC
#ifndef HAVE_TYPE_RB_ALLOC_FUNC_T
#define rb_alloc_func_t void*
#endif
  rb_define_alloc_func (c_guestfs, (rb_alloc_func_t) ruby_guestfs_alloc);
#endif

  rb_define_method (c_guestfs, \"initialize\", ruby_guestfs_initialize, -1);
  rb_define_method (c_guestfs, \"close\", ruby_guestfs_close, 0);
  rb_define_method (c_guestfs, \"set_event_callback\",
                    ruby_set_event_callback, 2);
  rb_define_method (c_guestfs, \"delete_event_callback\",
                    ruby_delete_event_callback, 1);
  rb_define_module_function (m_guestfs, \"event_to_string\",
                    ruby_event_to_string, 1);

  /* For backwards compatibility with older code, define a ::create
   * module function.
   */
  rb_define_module_function (m_guestfs, \"create\", ruby_guestfs_create, -1);

";

  (* Constants. *)
  List.iter (
    fun (name, bitmask) ->
      pr "  rb_define_const (m_guestfs, \"EVENT_%s\",\n"
        (String.uppercase name);
      pr "                   ULL2NUM (UINT64_C (0x%x)));\n" bitmask;
  ) events;
  pr "  rb_define_const (m_guestfs, \"EVENT_ALL\",\n";
  pr "                   ULL2NUM (UINT64_C (0x%x)));\n" all_events_bitmask;
  pr "\n";

  (* Methods. *)
  List.iter (
    fun { name = name; style = _, args, optargs;
          non_c_aliases = non_c_aliases } ->
      let nr_args = if optargs = [] then List.length args else -1 in
      pr "  rb_define_method (c_guestfs, \"%s\",\n" name;
      pr "        ruby_guestfs_%s, %d);\n" name nr_args;

      (* Aliases. *)
      List.iter (
        fun alias ->
          pr "  rb_define_method (c_guestfs, \"%s\",\n" alias;
          pr "        ruby_guestfs_%s, %d);\n" name nr_args
      ) non_c_aliases
  ) external_functions_sorted;

  pr "}\n"

(* Ruby code to return a struct. *)
and generate_ruby_struct_code typ cols =
  pr "  volatile VALUE rv = rb_hash_new ();\n";
  List.iter (
    function
    | name, FString ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), rb_str_new2 (r->%s));\n" name name
    | name, FBuffer ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), rb_str_new (r->%s, r->%s_len));\n" name name name
    | name, FUUID ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), rb_str_new (r->%s, 32));\n" name name
    | name, (FBytes|FUInt64) ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), ULL2NUM (r->%s));\n" name name
    | name, FInt64 ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), LL2NUM (r->%s));\n" name name
    | name, FUInt32 ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), UINT2NUM (r->%s));\n" name name
    | name, FInt32 ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), INT2NUM (r->%s));\n" name name
    | name, FOptPercent ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), rb_dbl2big (r->%s));\n" name name
    | name, FChar -> (* XXX wrong? *)
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), ULL2NUM (r->%s));\n" name name
  ) cols;
  pr "  guestfs_free_%s (r);\n" typ;
  pr "  return rv;\n"

(* Ruby code to return a struct list. *)
and generate_ruby_struct_list_code typ cols =
  pr "  volatile VALUE rv = rb_ary_new2 (r->len);\n";
  pr "  size_t i;\n";
  pr "  for (i = 0; i < r->len; ++i) {\n";
  pr "    volatile VALUE hv = rb_hash_new ();\n";
  List.iter (
    function
    | name, FString ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), rb_str_new2 (r->val[i].%s));\n" name name
    | name, FBuffer ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), rb_str_new (r->val[i].%s, r->val[i].%s_len));\n" name name name
    | name, FUUID ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), rb_str_new (r->val[i].%s, 32));\n" name name
    | name, (FBytes|FUInt64) ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), ULL2NUM (r->val[i].%s));\n" name name
    | name, FInt64 ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), LL2NUM (r->val[i].%s));\n" name name
    | name, FUInt32 ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), UINT2NUM (r->val[i].%s));\n" name name
    | name, FInt32 ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), INT2NUM (r->val[i].%s));\n" name name
    | name, FOptPercent ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), rb_dbl2big (r->val[i].%s));\n" name name
    | name, FChar -> (* XXX wrong? *)
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), ULL2NUM (r->val[i].%s));\n" name name
  ) cols;
  pr "    rb_ary_push (rv, hv);\n";
  pr "  }\n";
  pr "  guestfs_free_%s_list (r);\n" typ;
  pr "  return rv;\n"
