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

(* Generate ruby bindings. *)
let rec generate_ruby_c () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

#include <ruby.h>

#include \"guestfs.h\"

#include \"extconf.h\"

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
  VALUE val;

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

/*
 * call-seq:
 *   Guestfs::Guestfs.new() -> Guestfs::Guestfs
 *
 * Call
 * +guestfs_create+[http://libguestfs.org/guestfs.3.html#guestfs_create]
 * to create a new libguestfs handle.  The handle is represented in
 * Ruby as an instance of the Guestfs::Guestfs class.
 */
static VALUE
ruby_guestfs_create (VALUE m)
{
  guestfs_h *g;

  g = guestfs_create ();
  if (!g)
    rb_raise (e_Error, \"failed to create guestfs handle\");

  /* Don't print error messages to stderr by default. */
  guestfs_set_error_handler (g, NULL, NULL);

  /* Wrap it, and make sure the close function is called when the
   * handle goes away.
   */
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

  ruby_guestfs_free (g);
  DATA_PTR (gv) = NULL;

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

  root = guestfs_safe_malloc (g, sizeof *root);
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
  VALUE eventv, event_handlev, bufv, arrayv;
  VALUE argv[5];

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
  VALUE fn, eventv, event_handlev, bufv, arrayv;

  fn = argv[0];

  /* Check the Ruby callback still exists.  For reasons which are not
   * fully understood, even though we registered this as a global root,
   * it is still possible for the callback to go away (fn value remains
   * but its type changes from T_DATA to T_NONE).  (RHBZ#733297)
   */
  if (rb_type (fn) != T_NONE) {
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
  /* Callbacks aren't supposed to throw exceptions.  The best we
   * can do is to print the error.
   */
  fprintf (stderr, \"libguestfs: exception in callback: %%s\\n\",
           StringValueCStr (exn));

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
  r = guestfs_safe_malloc (g, sizeof (VALUE *) * (*len_rtn));

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

/*
 * call-seq:
 *   g.user_cancel() -> nil
 *
 * Call
 * +guestfs_user_cancel+[http://libguestfs.org/guestfs.3.html#guestfs_user_cancel]
 * to cancel the current transfer.  This is safe to call from Ruby
 * signal handlers and threads.
 */
static VALUE
ruby_user_cancel (VALUE gv)
{
  guestfs_h *g;

  Data_Get_Struct (gv, guestfs_h, g);
  if (g)
    guestfs_user_cancel (g);
  return Qnil;
}

";

  List.iter (
    fun (name, (ret, args, optargs as style), _, flags, _, shortdesc, longdesc) ->
      (* Generate rdoc. *)
      if not (List.mem NotInDocs flags); then (
        let doc = replace_str longdesc "C<guestfs_" "C<g." in
        let doc =
          if optargs <> [] then
            doc ^ "\n\nOptional arguments are supplied in the final hash parameter, which is a hash of the argument name to its value.  Pass an empty {} for no optional arguments."
          else doc in
        let doc =
          if List.mem ProtocolLimitWarning flags then
            doc ^ "\n\n" ^ protocol_limit_warning
          else doc in
        let doc =
          match deprecation_notice flags with
          | None -> doc
          | Some txt -> doc ^ "\n\n" ^ txt in
        let doc = pod2text ~width:60 name doc in
        let doc = String.concat "\n * " doc in
        let doc = trim doc in

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
" name args ret shortdesc doc name name
      );

      (* Generate the function. *)
      pr "static VALUE\n";
      pr "ruby_guestfs_%s (VALUE gv" name;
      List.iter (fun arg -> pr ", VALUE %sv" (name_of_argt arg)) args;
      (* XXX This makes the hash mandatory, meaning that you have
       * to specify {} for no arguments.  We could make it so this
       * can be omitted.  However that is a load of hassle because
       * you have to completely change the way that arguments are
       * passed in.  See:
       * http://www.redhat.com/archives/libvir-list/2008-April/msg00004.html
       *)
      if optargs <> [] then
        pr ", VALUE optargsv";
      pr ")\n";
      pr "{\n";
      pr "  guestfs_h *g;\n";
      pr "  Data_Get_Struct (gv, guestfs_h, g);\n";
      pr "  if (!g)\n";
      pr "    rb_raise (rb_eArgError, \"%%s: used handle after closing it\", \"%s\");\n"
        name;
      pr "\n";

      List.iter (
        function
        | Pathname n | Device n | Dev_or_Path n | String n | Key n
        | FileIn n | FileOut n ->
            pr "  const char *%s = StringValueCStr (%sv);\n" n n;
        | BufferIn n ->
            pr "  Check_Type (%sv, T_STRING);\n" n;
            pr "  const char *%s = RSTRING_PTR (%sv);\n" n n;
            pr "  if (!%s)\n" n;
            pr "    rb_raise (rb_eTypeError, \"expected string for parameter %%s of %%s\",\n";
            pr "              \"%s\", \"%s\");\n" n name;
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
            pr "      VALUE v = rb_ary_entry (%sv, i);\n" n;
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
        let uc_name = String.uppercase name in
        pr "  Check_Type (optargsv, T_HASH);\n";
        pr "  struct guestfs_%s_argv optargs_s = { .bitmask = 0 };\n" name;
        pr "  struct guestfs_%s_argv *optargs = &optargs_s;\n" name;
        pr "  VALUE v;\n";
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
            );
            pr "    optargs_s.bitmask |= GUESTFS_%s_%s_BITMASK;\n" uc_name uc_n;
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

      if optargs = [] then
        pr "  r = guestfs_%s " name
      else
        pr "  r = guestfs_%s_argv " name;
      generate_c_call_args ~handle:"g" style;
      pr ";\n";

      List.iter (
        function
        | Pathname _ | Device _ | Dev_or_Path _ | String _ | Key _
        | FileIn _ | FileOut _ | OptString _ | Bool _ | Int _ | Int64 _
        | BufferIn _ | Pointer _ -> ()
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
           pr "  VALUE rv = rb_str_new2 (r);\n";
           pr "  free (r);\n";
           pr "  return rv;\n";
       | RStringList _ ->
           pr "  size_t i, len = 0;\n";
           pr "  for (i = 0; r[i] != NULL; ++i) len++;\n";
           pr "  VALUE rv = rb_ary_new2 (len);\n";
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
           pr "  VALUE rv = rb_hash_new ();\n";
           pr "  size_t i;\n";
           pr "  for (i = 0; r[i] != NULL; i+=2) {\n";
           pr "    rb_hash_aset (rv, rb_str_new2 (r[i]), rb_str_new2 (r[i+1]));\n";
           pr "    free (r[i]);\n";
           pr "    free (r[i+1]);\n";
           pr "  }\n";
           pr "  free (r);\n";
           pr "  return rv;\n"
       | RBufferOut _ ->
           pr "  VALUE rv = rb_str_new (r, size);\n";
           pr "  free (r);\n";
           pr "  return rv;\n";
      );

      pr "}\n";
      pr "\n"
  ) all_functions;

  pr "\
/* Initialize the module. */
void Init__guestfs ()
{
  m_guestfs = rb_define_module (\"Guestfs\");
  c_guestfs = rb_define_class_under (m_guestfs, \"Guestfs\", rb_cObject);
  e_Error = rb_define_class_under (m_guestfs, \"Error\", rb_eStandardError);

#ifdef HAVE_RB_DEFINE_ALLOC_FUNC
  rb_define_alloc_func (c_guestfs, ruby_guestfs_create);
#endif

  rb_define_module_function (m_guestfs, \"create\", ruby_guestfs_create, 0);
  rb_define_method (c_guestfs, \"close\", ruby_guestfs_close, 0);
  rb_define_method (c_guestfs, \"set_event_callback\",
                    ruby_set_event_callback, 2);
  rb_define_method (c_guestfs, \"delete_event_callback\",
                    ruby_delete_event_callback, 1);
  rb_define_method (c_guestfs, \"user_cancel\",
                    ruby_user_cancel, 0);

";

  (* Constants. *)
  List.iter (
    fun (name, bitmask) ->
      pr "  rb_define_const (m_guestfs, \"EVENT_%s\",\n"
        (String.uppercase name);
      pr "                   ULL2NUM (UINT64_C (0x%x)));\n" bitmask;
  ) events;
  pr "\n";

  (* Methods. *)
  List.iter (
    fun (name, (_, args, optargs), _, _, _, _, _) ->
      let nr_args = List.length args + if optargs <> [] then 1 else 0 in
      pr "  rb_define_method (c_guestfs, \"%s\",\n" name;
      pr "        ruby_guestfs_%s, %d);\n" name nr_args
  ) all_functions;

  pr "}\n"

(* Ruby code to return a struct. *)
and generate_ruby_struct_code typ cols =
  pr "  VALUE rv = rb_hash_new ();\n";
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
  pr "  VALUE rv = rb_ary_new2 (r->len);\n";
  pr "  size_t i;\n";
  pr "  for (i = 0; i < r->len; ++i) {\n";
  pr "    VALUE hv = rb_hash_new ();\n";
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
