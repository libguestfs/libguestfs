(* libguestfs
 * Copyright (C) 2009-2016 Red Hat Inc.
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
open Events

let generate_header = generate_header ~inputs:["generator/c.ml"]

(* Generate C API. *)

(* The actions are split across this many C files.  You can increase
 * this number in order to reduce the number of lines in each file
 * (hence making compilation faster), but you also have to modify
 * src/Makefile.am.
 *)
let nr_actions_files = 7
let hash_matches h { name = name } =
  let h' = Hashtbl.hash name mod nr_actions_files in
  h = h'

type optarg_proto = Dots | VA | Argv

let is_public { visibility = v } = match v with
  | VPublic | VPublicNoFish | VStateTest | VDebug -> true
  | VBindTest | VInternal -> false

let is_private f = not (is_public f)

let public_functions_sorted =
  List.filter is_public all_functions_sorted

let private_functions_sorted =
  List.filter is_private all_functions_sorted

(* Generate a C function prototype. *)
let rec generate_prototype ?(extern = true) ?(static = false)
    ?(semicolon = true)
    ?(single_line = false) ?(indent = "") ?(newline = false)
    ?(in_daemon = false)
    ?(dll_public = false)
    ?(attribute_noreturn = false)
    ?(prefix = "") ?(suffix = "")
    ?handle
    ?(optarg_proto = Dots)
    name (ret, args, optargs) =
  pr "%s" indent;
  if extern then pr "extern ";
  if dll_public then pr "GUESTFS_DLL_PUBLIC ";
  if static then pr "static ";
  let space = ref false in
  (match ret with
   | RErr
   | RInt _
   | RBool _ ->
       pr "int";
       space := true
   | RInt64 _ ->
       pr "int64_t";
       space := true
   | RConstString _ | RConstOptString _ ->
       pr "const char *"
   | RString _ | RBufferOut _ ->
       pr "char *"
   | RStringList _ | RHashtable _ ->
       pr "char **"
   | RStruct (_, typ) ->
       if not in_daemon then pr "struct guestfs_%s *" typ
       else pr "guestfs_int_%s *" typ
   | RStructList (_, typ) ->
       if not in_daemon then pr "struct guestfs_%s_list *" typ
       else pr "guestfs_int_%s_list *" typ
  );
  if single_line && !space then pr " ";
  if attribute_noreturn then pr "__attribute__((noreturn)) ";
  if not single_line then pr "\n%s" indent;
  let is_RBufferOut = match ret with RBufferOut _ -> true | _ -> false in
  pr "%s%s%s (" prefix name suffix;

  let comma = ref false in
  (match handle with
   | None -> ()
   | Some handle -> pr "guestfs_h *%s" handle; comma := true
  );
  let next () =
    if !comma then (
      if single_line then pr ", "
      else (
        let namelen = String.length prefix + String.length name +
                      String.length suffix + 2 in
        pr ",\n%s%s" indent (spaces namelen)
      )
    );
    comma := true
  in
  List.iter (
    function
    | Pathname n
    | Device n | Dev_or_Path n
    | String n
    | OptString n
    | Key n
    | GUID n ->
        next ();
        pr "const char *%s" n
    | Mountable n | Mountable_or_Path n ->
        next();
        if in_daemon then
          pr "const mountable_t *%s" n
        else
          pr "const char *%s" n
    | StringList n | DeviceList n | FilenameList n ->
        next ();
        pr "char *const *%s" n
    | Bool n -> next (); pr "int %s" n
    | Int n -> next (); pr "int %s" n
    | Int64 n -> next (); pr "int64_t %s" n
    | FileIn n
    | FileOut n ->
        if not in_daemon then (next (); pr "const char *%s" n)
    | BufferIn n ->
        next ();
        pr "const char *%s" n;
        next ();
        pr "size_t %s_size" n
    | Pointer (t, n) ->
        next ();
        pr "void * /* really %s */ %s" t n
  ) args;
  if is_RBufferOut then (next (); pr "size_t *size_r");
  if optargs <> [] then (
    next ();
    match optarg_proto with
    | Dots -> pr "..."
    | VA -> pr "va_list args"
    | Argv -> pr "const struct guestfs_%s_argv *optargs" name
  );

  (* Was anything output between ()?  If not, it's a 'function(void)'. *)
  if !comma = false then pr "void";

  pr ")";
  if semicolon then pr ";";
  if newline then pr "\n"

(* Generate C call arguments, eg "(handle, foo, bar)" *)
and generate_c_call_args ?handle ?(implicit_size_ptr = "&size")
    ?(in_daemon = false)
    (ret, args, optargs) =
  pr "(";
  let comma = ref false in
  let next () =
    if !comma then pr ", ";
    comma := true
  in
  (match handle with
   | None -> ()
   | Some handle -> pr "%s" handle; comma := true
  );
  List.iter (
    function
    | BufferIn n ->
        next ();
        pr "%s, %s_size" n n
    | Mountable n | Mountable_or_Path n ->
        next ();
        (if in_daemon then pr "&%s" else pr "%s") n
    | arg ->
        next ();
        pr "%s" (name_of_argt arg)
  ) args;
  (* For RBufferOut calls, add implicit size pointer parameter. *)
  (match ret with
   | RBufferOut _ ->
       next ();
       pr "%s" implicit_size_ptr
   | _ -> ()
  );
  (* For calls with optional arguments, add implicit optargs parameter. *)
  if optargs <> [] then (
    next ();
    pr "optargs"
  );
  pr ")"

(* Generate the pod documentation for the C API. *)
and generate_actions_pod () =
  generate_header PODStyle GPLv2plus;

  List.iter (
    function
    | ({ once_had_no_optargs = false } as f) ->
      generate_actions_pod_entry f
    | ({ once_had_no_optargs = true } as f) ->
      generate_actions_pod_back_compat_entry f;
      generate_actions_pod_entry f
  ) documented_functions_sorted

and generate_actions_pod_entry ({ c_name = c_name;
                                  style = ret, args, optargs as style } as f) =
  pr "=head2 guestfs_%s\n\n" c_name;
  generate_prototype ~extern:false ~indent:" " ~handle:"g"
    ~prefix:"guestfs_" c_name style;
  pr "\n\n";

  (match deprecation_notice ~prefix:"guestfs_" f with
  | None -> ()
  | Some txt -> pr "%s\n\n" txt
  );

  if optargs <> [] then (
    pr "You may supply a list of optional arguments to this call.\n";
    pr "Use zero or more of the following pairs of parameters,\n";
    pr "and terminate the list with C<-1> on its own.\n";
    pr "See L</CALLS WITH OPTIONAL ARGUMENTS>.\n\n";
    List.iter (
      fun argt ->
        let n = name_of_optargt argt in
        pr " GUESTFS_%s_%s, " (String.uppercase c_name) (String.uppercase n);
        match argt with
        | OBool n -> pr "int %s,\n" n
        | OInt n -> pr "int %s,\n" n
        | OInt64 n -> pr "int64_t %s,\n" n
        | OString n -> pr "const char *%s,\n" n
        | OStringList n -> pr "char *const *%s,\n" n
    ) optargs;
    pr "\n";
  );

  pr "%s\n\n" f.longdesc;
  let ret, args, optargs = style in
  (match ret with
  | RErr ->
    pr "This function returns 0 on success or -1 on error.\n\n"
  | RInt _ ->
    pr "On error this function returns -1.\n\n"
  | RInt64 _ ->
    pr "On error this function returns -1.\n\n"
  | RBool _ ->
    pr "This function returns a C truth value on success or -1 on error.\n\n"
  | RConstString _ ->
    pr "This function returns a string, or NULL on error.
The string is owned by the guest handle and must I<not> be freed.\n\n"
  | RConstOptString _ ->
    pr "This function returns a string which may be NULL.
There is no way to return an error from this function.
The string is owned by the guest handle and must I<not> be freed.\n\n"
  | RString _ ->
    pr "This function returns a string, or NULL on error.
I<The caller must free the returned string after use>.\n\n"
  | RStringList _ ->
    pr "This function returns a NULL-terminated array of strings
(like L<environ(3)>), or NULL if there was an error.
I<The caller must free the strings and the array after use>.\n\n"
  | RStruct (_, typ) ->
    pr "This function returns a C<struct guestfs_%s *>,
or NULL if there was an error.
I<The caller must call C<guestfs_free_%s> after use>.\n\n" typ typ
  | RStructList (_, typ) ->
    pr "This function returns a C<struct guestfs_%s_list *>,
or NULL if there was an error.
I<The caller must call C<guestfs_free_%s_list> after use>.\n\n" typ typ
  | RHashtable _ ->
    pr "This function returns a NULL-terminated array of
strings, or NULL if there was an error.
The array of strings will always have length C<2n+1>, where
C<n> keys and values alternate, followed by the trailing NULL entry.
I<The caller must free the strings and the array after use>.\n\n"
  | RBufferOut _ ->
    pr "This function returns a buffer, or NULL on error.
The size of the returned buffer is written to C<*size_r>.
I<The caller must free the returned buffer after use>.\n\n"
  );
  if f.progress then
    pr "%s\n\n" progress_message;
  if f.protocol_limit_warning then
    pr "%s\n\n" protocol_limit_warning;
  if List.exists (function Key _ -> true | _ -> false) args then
    pr "This function takes a key or passphrase parameter which
could contain sensitive material.  Read the section
L</KEYS AND PASSPHRASES> for more information.\n\n";
  (match f.optional with
  | None -> ()
  | Some opt ->
    pr "This function depends on the feature C<%s>.  See also
L</guestfs_feature_available>.\n\n" opt
  );
  (match version_added f with
  | Some version -> pr "(Added in %s)\n\n" version
  | None -> assert false
  );

  (* Handling of optional argument variants. *)
  if optargs <> [] then (
    pr "=head2 guestfs_%s_va\n\n" c_name;
    generate_prototype ~extern:false ~indent:" " ~handle:"g"
      ~prefix:"guestfs_" ~suffix:"_va" ~optarg_proto:VA
      c_name style;
    pr "\n\n";
    pr "This is the \"va_list variant\" of L</guestfs_%s>.\n\n" c_name;
    pr "See L</CALLS WITH OPTIONAL ARGUMENTS>.\n\n";
    pr "=head2 guestfs_%s_argv\n\n" c_name;
    generate_prototype ~extern:false ~indent:" " ~handle:"g"
      ~prefix:"guestfs_" ~suffix:"_argv" ~optarg_proto:Argv
      c_name style;
    pr "\n\n";
    pr "This is the \"argv variant\" of L</guestfs_%s>.\n\n" c_name;
    pr "See L</CALLS WITH OPTIONAL ARGUMENTS>.\n\n";
  )

and generate_actions_pod_back_compat_entry ({ name = name;
                                              style = ret, args, _ } as f) =
  pr "=head2 guestfs_%s\n\n" name;
  generate_prototype ~extern:false ~indent:" " ~handle:"g"
    ~prefix:"guestfs_" name (ret, args, []);
  pr "\n\n";

  pr "This function is provided for backwards compatibility\n";
  pr "with earlier versions of libguestfs.  It simply calls\n";
  pr "L</guestfs_%s_opts> with no optional arguments.\n" name;
  pr "\n";

  (match version_added f with
  | Some version -> pr "(Added in %s)\n\n\n" version
  | None -> assert false
  )

and generate_structs_pod () =
  generate_header PODStyle GPLv2plus;

  (* Structs documentation. *)
  List.iter (
    fun { s_name = typ; s_cols = cols } ->
      pr "=head2 guestfs_%s\n" typ;
      pr "\n";
      pr " struct guestfs_%s {\n" typ;
      List.iter (
        function
        | name, FChar -> pr "   char %s;\n" name
        | name, FUInt32 -> pr "   uint32_t %s;\n" name
        | name, FInt32 -> pr "   int32_t %s;\n" name
        | name, (FUInt64|FBytes) -> pr "   uint64_t %s;\n" name
        | name, FInt64 -> pr "   int64_t %s;\n" name
        | name, FString -> pr "   char *%s;\n" name
        | name, FBuffer ->
            pr "   /* The next two fields describe a byte array. */\n";
            pr "   uint32_t %s_len;\n" name;
            pr "   char *%s;\n" name
        | name, FUUID ->
            pr "   /* The next field is NOT nul-terminated, be careful when printing it: */\n";
            pr "   char %s[32];\n" name
        | name, FOptPercent ->
            pr "   /* The next field is [0..100] or -1 meaning 'not present': */\n";
            pr "   float %s;\n" name
      ) cols;
      pr " };\n";
      pr " \n";
      pr " struct guestfs_%s_list {\n" typ;
      pr "   uint32_t len; /* Number of elements in list. */\n";
      pr "   struct guestfs_%s *val; /* Elements. */\n" typ;
      pr " };\n";
      pr "\n";
      pr " int guestfs_compare_%s (const struct guestfs_%s *, const struct guestfs_%s *);\n"
        typ typ typ;
      pr " int guestfs_compare_%s_list (const struct guestfs_%s_list *, const struct guestfs_%s_list *);\n"
        typ typ typ;
      pr " \n";
      pr " struct guestfs_%s *guestfs_copy_%s (const struct guestfs_%s *);\n"
        typ typ typ;
      pr " struct guestfs_%s_list *guestfs_copy_%s_list (const struct guestfs_%s_list *);\n"
        typ typ typ;
      pr " \n";
      pr " void guestfs_free_%s (struct guestfs_%s *);\n" typ typ;
      pr " void guestfs_free_%s_list (struct guestfs_%s_list *);\n"
        typ typ;
      pr "\n"
  ) structs

and generate_availability_pod () =
  generate_header PODStyle GPLv2plus;

  (* Availability documentation. *)
  pr "=over 4\n";
  pr "\n";
  List.iter (
    fun (group, fns) ->
      pr "=item B<%s>\n" group;
      pr "\n";
      pr "The following functions:\n";
      List.iter (pr "L</guestfs_%s>\n") (List.map (fun { name = n } -> n) fns);
      pr "\n"
  ) optgroups;
  pr "=back\n";
  pr "\n"

(* Generate the guestfs.h file. *)
and generate_guestfs_h () =
  generate_header CStyle LGPLv2plus;

  pr "\
/* ---------- IMPORTANT NOTE ----------
 *
 * All API documentation is in the manpage, 'guestfs(3)'.
 * To read it, type:           man 3 guestfs
 * Or read it online here:     http://libguestfs.org/guestfs.3.html
 *
 * Go and read it now!  This header file won't make much sense.
 *
 * For example code using the C API, see 'guestfs-examples(3)'
 * available online at: http://libguestfs.org/guestfs-examples.3.html
 *
 * ------------------------------------
 */

#ifndef GUESTFS_H_
#define GUESTFS_H_

#ifdef __cplusplus
extern \"C\" {
#endif

#include <stddef.h>
#include <stdint.h>
#include <stdarg.h>

#if defined(__GNUC__) && !defined(GUESTFS_GCC_VERSION)
# define GUESTFS_GCC_VERSION \\
    (__GNUC__ * 10000 + __GNUC_MINOR__ * 100 + __GNUC_PATCHLEVEL__)
#endif

/* Define GUESTFS_WARN_DEPRECATED=1 to warn about deprecated API functions. */
#define GUESTFS_DEPRECATED_BY(s)
#if GUESTFS_WARN_DEPRECATED
#  if defined(__GNUC__) && GUESTFS_GCC_VERSION >= 40500 /* gcc >= 4.5 */
#    undef GUESTFS_DEPRECATED_BY
#    define GUESTFS_DEPRECATED_BY(s) __attribute__((__deprecated__(\"change the program to use guestfs_\" s \" instead of this deprecated function\")))
#  endif
#endif /* GUESTFS_WARN_DEPRECATED */

#if defined(__GNUC__) && GUESTFS_GCC_VERSION >= 40000 /* gcc >= 4.0 */
# define GUESTFS_DLL_PUBLIC __attribute__((visibility (\"default\")))
#else
# define GUESTFS_DLL_PUBLIC
#endif

#if defined(__GNUC__) && GUESTFS_GCC_VERSION >= 30100 /* gcc >= 3.1 */
# define GUESTFS_NORETURN __attribute__((noreturn))
#else
# define GUESTFS_NORETURN
#endif

/* The handle. */
#ifndef GUESTFS_TYPEDEF_H
#define GUESTFS_TYPEDEF_H 1
typedef struct guestfs_h guestfs_h;
#endif

/* Connection management. */
extern GUESTFS_DLL_PUBLIC guestfs_h *guestfs_create (void);
#define GUESTFS_HAVE_CREATE_FLAGS 1
extern GUESTFS_DLL_PUBLIC guestfs_h *guestfs_create_flags (unsigned flags, ...);
#define GUESTFS_CREATE_NO_ENVIRONMENT   (1 << 0)
#define GUESTFS_CREATE_NO_CLOSE_ON_EXIT (1 << 1)
extern GUESTFS_DLL_PUBLIC void guestfs_close (guestfs_h *g);

/* Error handling. */
extern GUESTFS_DLL_PUBLIC const char *guestfs_last_error (guestfs_h *g);
#define GUESTFS_HAVE_LAST_ERRNO 1
extern GUESTFS_DLL_PUBLIC int guestfs_last_errno (guestfs_h *g);

#ifndef GUESTFS_TYPEDEF_ERROR_HANDLER_CB
#define GUESTFS_TYPEDEF_ERROR_HANDLER_CB 1
typedef void (*guestfs_error_handler_cb) (guestfs_h *g, void *opaque, const char *msg);
#endif

#ifndef GUESTFS_TYPEDEF_ABORT_CB
#define GUESTFS_TYPEDEF_ABORT_CB 1
typedef void (*guestfs_abort_cb) (void) GUESTFS_NORETURN;
#endif

extern GUESTFS_DLL_PUBLIC void guestfs_set_error_handler (guestfs_h *g, guestfs_error_handler_cb cb, void *opaque);
extern GUESTFS_DLL_PUBLIC guestfs_error_handler_cb guestfs_get_error_handler (guestfs_h *g, void **opaque_rtn);
#define GUESTFS_HAVE_PUSH_ERROR_HANDLER 1
extern GUESTFS_DLL_PUBLIC void guestfs_push_error_handler (guestfs_h *g, guestfs_error_handler_cb cb, void *opaque);
#define GUESTFS_HAVE_POP_ERROR_HANDLER 1
extern GUESTFS_DLL_PUBLIC void guestfs_pop_error_handler (guestfs_h *g);

extern GUESTFS_DLL_PUBLIC void guestfs_set_out_of_memory_handler (guestfs_h *g, guestfs_abort_cb);
extern GUESTFS_DLL_PUBLIC guestfs_abort_cb guestfs_get_out_of_memory_handler (guestfs_h *g);

/* Events. */
";

  List.iter (
    fun (name, bitmask) ->
      pr "#define GUESTFS_EVENT_%-16s 0x%04x\n"
        (String.uppercase name) bitmask
  ) events;
  pr "#define GUESTFS_EVENT_%-16s 0x%04x\n" "ALL" all_events_bitmask;
  pr "\n";

  pr "\
#ifndef GUESTFS_TYPEDEF_EVENT_CALLBACK
#define GUESTFS_TYPEDEF_EVENT_CALLBACK 1
typedef void (*guestfs_event_callback) (
                        guestfs_h *g,
                        void *opaque,
                        uint64_t event,
                        int event_handle,
                        int flags,
                        const char *buf, size_t buf_len,
                        const uint64_t *array, size_t array_len);
#endif

#define GUESTFS_HAVE_SET_EVENT_CALLBACK 1
extern GUESTFS_DLL_PUBLIC int guestfs_set_event_callback (guestfs_h *g, guestfs_event_callback cb, uint64_t event_bitmask, int flags, void *opaque);
#define GUESTFS_HAVE_DELETE_EVENT_CALLBACK 1
extern GUESTFS_DLL_PUBLIC void guestfs_delete_event_callback (guestfs_h *g, int event_handle);
#define GUESTFS_HAVE_EVENT_TO_STRING 1
extern GUESTFS_DLL_PUBLIC char *guestfs_event_to_string (uint64_t event);

/* Old-style event handling. */
#ifndef GUESTFS_TYPEDEF_LOG_MESSAGE_CB
#define GUESTFS_TYPEDEF_LOG_MESSAGE_CB 1
typedef void (*guestfs_log_message_cb) (guestfs_h *g, void *opaque, char *buf, int len);
#endif

#ifndef GUESTFS_TYPEDEF_SUBPROCESS_QUIT_CB
#define GUESTFS_TYPEDEF_SUBPROCESS_QUIT_CB 1
typedef void (*guestfs_subprocess_quit_cb) (guestfs_h *g, void *opaque);
#endif

#ifndef GUESTFS_TYPEDEF_LAUNCH_DONE_CB
#define GUESTFS_TYPEDEF_LAUNCH_DONE_CB 1
typedef void (*guestfs_launch_done_cb) (guestfs_h *g, void *opaque);
#endif

#ifndef GUESTFS_TYPEDEF_CLOSE_CB
#define GUESTFS_TYPEDEF_CLOSE_CB 1
typedef void (*guestfs_close_cb) (guestfs_h *g, void *opaque);
#endif

#ifndef GUESTFS_TYPEDEF_PROGRESS_CB
#define GUESTFS_TYPEDEF_PROGRESS_CB 1
typedef void (*guestfs_progress_cb) (guestfs_h *g, void *opaque, int proc_nr, int serial, uint64_t position, uint64_t total);
#endif

extern GUESTFS_DLL_PUBLIC void guestfs_set_log_message_callback (guestfs_h *g, guestfs_log_message_cb cb, void *opaque)
  GUESTFS_DEPRECATED_BY(\"set_event_callback\");
extern GUESTFS_DLL_PUBLIC void guestfs_set_subprocess_quit_callback (guestfs_h *g, guestfs_subprocess_quit_cb cb, void *opaque)
  GUESTFS_DEPRECATED_BY(\"set_event_callback\");
extern GUESTFS_DLL_PUBLIC void guestfs_set_launch_done_callback (guestfs_h *g, guestfs_launch_done_cb cb, void *opaque)
  GUESTFS_DEPRECATED_BY(\"set_event_callback\");
#define GUESTFS_HAVE_SET_CLOSE_CALLBACK 1
extern GUESTFS_DLL_PUBLIC void guestfs_set_close_callback (guestfs_h *g, guestfs_close_cb cb, void *opaque)
  GUESTFS_DEPRECATED_BY(\"set_event_callback\");
#define GUESTFS_HAVE_SET_PROGRESS_CALLBACK 1
extern GUESTFS_DLL_PUBLIC void guestfs_set_progress_callback (guestfs_h *g, guestfs_progress_cb cb, void *opaque)
  GUESTFS_DEPRECATED_BY(\"set_event_callback\");

/* Private data area. */
#define GUESTFS_HAVE_SET_PRIVATE 1
extern GUESTFS_DLL_PUBLIC void guestfs_set_private (guestfs_h *g, const char *key, void *data);
#define GUESTFS_HAVE_GET_PRIVATE 1
extern GUESTFS_DLL_PUBLIC void *guestfs_get_private (guestfs_h *g, const char *key);
#define GUESTFS_HAVE_FIRST_PRIVATE 1
extern GUESTFS_DLL_PUBLIC void *guestfs_first_private (guestfs_h *g, const char **key_rtn);
#define GUESTFS_HAVE_NEXT_PRIVATE 1
extern GUESTFS_DLL_PUBLIC void *guestfs_next_private (guestfs_h *g, const char **key_rtn);

/* Structures. */
";

  (* The structures are carefully written to have exactly the same
   * in-memory format as the XDR structures that we use on the wire to
   * the daemon.  The reason for creating copies of these structures
   * here is just so we don't have to export the whole of
   * guestfs_protocol.h (which includes much unrelated and
   * XDR-dependent stuff that we don't want to be public, or required
   * by clients).
   *
   * To reiterate, we will pass these structures to and from the client
   * with a simple assignment or memcpy, so the format must be
   * identical to what rpcgen / the RFC defines.
   *)

  (* Public structures. *)
  let generate_all_structs = List.iter (
    fun { s_name = typ; s_cols = cols } ->
      pr "#define GUESTFS_HAVE_STRUCT_%s 1\n" (String.uppercase typ);
      pr "\n";
      pr "struct guestfs_%s {\n" typ;
      List.iter (
        function
        | name, FChar -> pr "  char %s;\n" name
        | name, FString -> pr "  char *%s;\n" name
        | name, FBuffer ->
            pr "  uint32_t %s_len;\n" name;
            pr "  char *%s;\n" name
        | name, FUUID -> pr "  char %s[32]; /* this is NOT nul-terminated, be careful when printing */\n" name
        | name, FUInt32 -> pr "  uint32_t %s;\n" name
        | name, FInt32 -> pr "  int32_t %s;\n" name
        | name, (FUInt64|FBytes) -> pr "  uint64_t %s;\n" name
        | name, FInt64 -> pr "  int64_t %s;\n" name
        | name, FOptPercent -> pr "  float %s; /* [0..100] or -1 */\n" name
      ) cols;
      pr "};\n";
      pr "\n";
      pr "struct guestfs_%s_list {\n" typ;
      pr "  uint32_t len;\n";
      pr "  struct guestfs_%s *val;\n" typ;
      pr "};\n";
      pr "\n";
      pr "extern GUESTFS_DLL_PUBLIC int guestfs_compare_%s (const struct guestfs_%s *, const struct guestfs_%s *);\n" typ typ typ;
      pr "extern GUESTFS_DLL_PUBLIC int guestfs_compare_%s_list (const struct guestfs_%s_list *, const struct guestfs_%s_list *);\n" typ typ typ;
      pr "\n";
      pr "extern GUESTFS_DLL_PUBLIC struct guestfs_%s *guestfs_copy_%s (const struct guestfs_%s *);\n" typ typ typ;
      pr "extern GUESTFS_DLL_PUBLIC struct guestfs_%s_list *guestfs_copy_%s_list (const struct guestfs_%s_list *);\n" typ typ typ;
      pr "\n";
      pr "extern GUESTFS_DLL_PUBLIC void guestfs_free_%s (struct guestfs_%s *);\n" typ typ;
      pr "extern GUESTFS_DLL_PUBLIC void guestfs_free_%s_list (struct guestfs_%s_list *);\n" typ typ;
      pr "\n"
  ) in

  generate_all_structs external_structs;

  pr "\
/* Actions. */
";

  let generate_action_header { name = shortname;
                               style = ret, args, optargs as style;
                               deprecated_by = deprecated_by } =
    pr "#define GUESTFS_HAVE_%s 1\n" (String.uppercase shortname);

    if optargs <> [] then (
      iteri (
        fun i argt ->
          let uc_shortname = String.uppercase shortname in
          let n = name_of_optargt argt in
          let uc_n = String.uppercase n in
          pr "#define GUESTFS_%s_%s %d\n" uc_shortname uc_n i;
      ) optargs;
    );

    generate_prototype ~single_line:true ~semicolon:false ~dll_public:true
      ~handle:"g" ~prefix:"guestfs_" shortname style;
    (match deprecated_by with
    | Some fn -> pr "\n  GUESTFS_DEPRECATED_BY (%S);\n" fn
    | None -> pr ";\n"
    );

    if optargs <> [] then (
      generate_prototype ~single_line:true ~newline:true ~handle:"g"
        ~prefix:"guestfs_" ~suffix:"_va" ~optarg_proto:VA
        ~dll_public:true
        shortname style;

      pr "\n";
      pr "struct guestfs_%s_argv {\n" shortname;
      pr "  uint64_t bitmask;\n";
      iteri (
        fun i argt ->
          let c_type =
            match argt with
            | OBool n -> "int "
            | OInt n -> "int "
            | OInt64 n -> "int64_t "
            | OString n -> "const char *"
            | OStringList n -> "char *const *" in
          let uc_shortname = String.uppercase shortname in
          let n = name_of_optargt argt in
          let uc_n = String.uppercase n in
          pr "# define GUESTFS_%s_%s_BITMASK (UINT64_C(1)<<%d)\n" uc_shortname uc_n i;
          pr "  %s%s;\n" c_type n
      ) optargs;
      pr "};\n";
      pr "\n";

      generate_prototype ~single_line:true ~newline:true ~handle:"g"
        ~prefix:"guestfs_" ~suffix:"_argv" ~optarg_proto:Argv
        ~dll_public:true
        shortname style;
    );

    pr "\n"
  in

  let generate_all_headers = List.iter (
    fun ({ name = name; style = ret, args, _ } as f) ->
      (* If once_had_no_optargs is set, then we need to generate a
       * <name>_opts variant, plus a backwards-compatible wrapper
       * called just <name> with no optargs.
       *)
      if f.once_had_no_optargs then (
        generate_action_header { f with style = ret, args, [] };
        generate_action_header { f with name = f.name ^ "_opts" };
      )
      else
        generate_action_header f
  ) in

  generate_all_headers public_functions_sorted;

  pr "\
#if GUESTFS_PRIVATE
/* Symbols protected by GUESTFS_PRIVATE are NOT part of the public,
 * stable API, and can change at any time!  We export them because
 * they are used by some of the language bindings.
 */

/* Private functions. */

";

  generate_all_headers private_functions_sorted;

  pr "\
/* Private structures. */

";

  generate_all_structs internal_structs;

pr "\

#endif /* End of GUESTFS_PRIVATE. */

/* Deprecated macros.  Use GUESTFS_HAVE_* instead. */

#define LIBGUESTFS_HAVE_CREATE_FLAGS 1
#define LIBGUESTFS_HAVE_LAST_ERRNO 1
#define LIBGUESTFS_HAVE_PUSH_ERROR_HANDLER 1
#define LIBGUESTFS_HAVE_POP_ERROR_HANDLER 1
#define LIBGUESTFS_HAVE_SET_EVENT_CALLBACK 1
#define LIBGUESTFS_HAVE_DELETE_EVENT_CALLBACK 1
#define LIBGUESTFS_HAVE_SET_CLOSE_CALLBACK 1
#define LIBGUESTFS_HAVE_SET_PROGRESS_CALLBACK 1
#define LIBGUESTFS_HAVE_SET_PRIVATE 1
#define LIBGUESTFS_HAVE_GET_PRIVATE 1
#define LIBGUESTFS_HAVE_FIRST_PRIVATE 1
#define LIBGUESTFS_HAVE_NEXT_PRIVATE 1

";

  List.iter (
    fun { name = shortname } ->
      pr "#define LIBGUESTFS_HAVE_%s 1\n" (String.uppercase shortname);
  ) public_functions_sorted;

  pr "
/* End of deprecated macros. */

#ifdef __cplusplus
}
#endif

#endif /* GUESTFS_H_ */
"

(* Generate the guestfs-internal-actions.h file. *)
and generate_internal_actions_h () =
  generate_header CStyle LGPLv2plus;

  pr "#ifndef GUESTFS_INTERNAL_ACTIONS_H_\n";
  pr "#define GUESTFS_INTERNAL_ACTIONS_H_\n";
  pr "\n";

  List.iter (
    fun { c_name = c_name; style = style } ->
      generate_prototype ~single_line:true ~newline:true ~handle:"g"
        ~prefix:"guestfs_impl_" ~optarg_proto:Argv
        c_name style
  ) non_daemon_functions;

  pr "\n";
  pr "#endif /* GUESTFS_INTERNAL_ACTIONS_H_ */\n"

(* Generate guestfs-internal-frontend-cleanups.h file. *)
and generate_internal_frontend_cleanups_h () =
  generate_header CStyle LGPLv2plus;

  pr "\
/* These CLEANUP_* macros automatically free the struct or struct list
 * pointed to by the local variable at the end of the current scope.
 *
 * Don't include this file directly!  To use these cleanups in library
 * bindings and tools, include \"guestfs-internal-frontend.h\" only.
 */

#ifndef GUESTFS_INTERNAL_FRONTEND_CLEANUPS_H_
#define GUESTFS_INTERNAL_FRONTEND_CLEANUPS_H_

#ifdef HAVE_ATTRIBUTE_CLEANUP
";

  List.iter (
    fun { s_name = name } ->
      pr "#define CLEANUP_FREE_%s \\\n" (String.uppercase name);
      pr "  __attribute__((cleanup(guestfs_int_cleanup_free_%s)))\n" name;
      pr "#define CLEANUP_FREE_%s_LIST \\\n" (String.uppercase name);
      pr "  __attribute__((cleanup(guestfs_int_cleanup_free_%s_list)))\n" name
  ) structs;

  pr "#else /* !HAVE_ATTRIBUTE_CLEANUP */\n";

  List.iter (
    fun { s_name = name } ->
      pr "#define CLEANUP_FREE_%s\n" (String.uppercase name);
      pr "#define CLEANUP_FREE_%s_LIST\n" (String.uppercase name)
  ) structs;

  pr "\
#endif /* !HAVE_ATTRIBUTE_CLEANUP */

/* These functions are used internally by the CLEANUP_* macros.
 * Don't call them directly.
 */

";

  List.iter (
    fun { s_name = name } ->
      pr "extern void guestfs_int_cleanup_free_%s (void *ptr);\n"
        name;
      pr "extern void guestfs_int_cleanup_free_%s_list (void *ptr);\n"
        name
  ) structs;

  pr "\n";
  pr "#endif /* GUESTFS_INTERNAL_FRONTEND_CLEANUPS_H_ */\n"

(* Functions to free structures. *)
and generate_client_structs_free () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>

#include \"guestfs.h\"
#include \"guestfs-internal.h\"
#include \"guestfs_protocol.h\"

";

  pr "/* Structure-freeing functions.  These rely on the fact that the\n";
  pr " * structure format is identical to the XDR format.  See note in\n";
  pr " * generator.ml.\n";
  pr " */\n";
  pr "\n";

  List.iter (
    fun { s_name = typ } ->
      pr "GUESTFS_DLL_PUBLIC void\n";
      pr "guestfs_free_%s (struct guestfs_%s *x)\n" typ typ;
      pr "{\n";
      pr "  if (x) {\n";
      pr "    xdr_free ((xdrproc_t) xdr_guestfs_int_%s, (char *) x);\n" typ;
      pr "    free (x);\n";
      pr "  }\n";
      pr "}\n";
      pr "\n";

      pr "GUESTFS_DLL_PUBLIC void\n";
      pr "guestfs_free_%s_list (struct guestfs_%s_list *x)\n" typ typ;
      pr "{\n";
      pr "  if (x) {\n";
      pr "    xdr_free ((xdrproc_t) xdr_guestfs_int_%s_list, (char *) x);\n"
        typ;
      pr "    free (x);\n";
      pr "  }\n";
      pr "}\n";
      pr "\n";

  ) structs

(* Functions to compare structures. *)
and generate_client_structs_compare () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#include \"guestfs.h\"
#include \"guestfs-internal.h\"

";

  pr "/* Structure-comparison functions. */\n";

  List.iter (
    fun { s_name = typ; s_cols = cols } ->
      let has_nonnumeric_cols =
        let nonnumeric = function
          | _,(FString|FUUID|FBuffer) -> true
          | _,(FChar|FUInt32|FInt32|FUInt64|FBytes|FInt64|FOptPercent) -> false
        in
        List.exists nonnumeric cols in

      pr "\n";
      pr "GUESTFS_DLL_PUBLIC int\n";
      pr "guestfs_compare_%s (const struct guestfs_%s *s1, const struct guestfs_%s *s2)\n"
        typ typ typ;
      pr "{\n";
      if has_nonnumeric_cols then (
        pr "  int r;\n";
        pr "\n";
      );
      List.iter (
        function
        | name, FString ->
          pr "  r = strcmp (s1->%s, s2->%s);\n" name name;
          pr "  if (r != 0) return r;\n"
        | name, FBuffer ->
          pr "  if (s1->%s_len < s2->%s_len) return -1;\n" name name;
          pr "  else if (s1->%s_len > s2->%s_len) return 1;\n" name name;
          pr "  else {\n";
          pr "    r = memcmp (s1->%s, s2->%s, s1->%s_len);\n" name name name;
          pr "    if (r != 0) return r;\n";
          pr "  }\n"
        | name, FUUID ->
          pr "  r = memcmp (s1->%s, s2->%s, 32 * sizeof (char));\n" name name;
          pr "  if (r != 0) return r;\n"
        | name, FChar
        | name, FUInt32
        | name, FInt32
        | name, FUInt64
        | name, FBytes
        | name, FInt64
        | name, FOptPercent ->
          pr "  if (s1->%s < s2->%s) return -1;\n" name name;
          pr "  else if (s1->%s > s2->%s) return 1;\n" name name
      ) cols;
      pr "  return 0;\n";
      pr "}\n";

      pr "\n";
      pr "GUESTFS_DLL_PUBLIC int\n";
      pr "guestfs_compare_%s_list (const struct guestfs_%s_list *s1, const struct guestfs_%s_list *s2)\n"
        typ typ typ;
      pr "{\n";
      pr "  if (s1->len < s2->len) return -1;\n";
      pr "  else if (s1->len > s2->len) return 1;\n";
      pr "  else {\n";
      pr "    size_t i;\n";
      pr "    int r;\n";
      pr "\n";
      pr "    for (i = 0; i < s1->len; ++i) {\n";
      pr "      r = guestfs_compare_%s (&s1->val[i], &s2->val[i]);\n" typ;
      pr "      if (r != 0) return r;\n";
      pr "    }\n";
      pr "    return 0;\n";
      pr "  }\n";
      pr "}\n"
  ) structs

(* Functions to copy structures. *)
and generate_client_structs_copy () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#include \"guestfs.h\"
#include \"guestfs-internal.h\"

";

  pr "/* Structure-copying functions. */\n";

  List.iter (
    fun { s_name = typ; s_cols = cols } ->
      let has_boxed_cols =
        let boxed = function
          | _,(FString|FBuffer) -> true
          | _,(FChar|FUUID|FUInt32|FInt32|FUInt64|FBytes|FInt64|FOptPercent) ->
            false
        in
        List.exists boxed cols in

      if has_boxed_cols then (
        pr "\n";
        pr "static void\n";
        pr "free_%s (struct guestfs_%s *s)\n" typ typ;
        pr "{\n";
        List.iter (
          function
          | name, FString
          | name, FBuffer -> pr "  free (s->%s);\n" name
          | _, FChar
          | _, FUUID
          | _, FUInt32
          | _, FInt32
          | _, FUInt64
          | _, FBytes
          | _, FInt64
          | _, FOptPercent -> ()
        ) cols;
        pr "}\n"
      );

      pr "\n";
      if has_boxed_cols then (
        pr "static int\n";
        pr "copy_%s (const struct guestfs_%s *inp, struct guestfs_%s *out)\n"
          typ typ typ;
        pr "{\n";
        pr "  int err;\n";
        pr "\n";
        List.iter (
          function
          | name, FString
          | name, FBuffer -> pr "  out->%s = NULL;\n" name
          | _, FChar
          | _, FUUID
          | _, FUInt32
          | _, FInt32
          | _, FUInt64
          | _, FBytes
          | _, FInt64
          | _, FOptPercent -> ()
        ) cols;
        List.iter (
          function
          | name, FString ->
            pr "  out->%s = strdup (inp->%s);\n" name name;
            pr "  if (out->%s == NULL) goto error;\n" name
          | name, FBuffer ->
            pr "  /* This adds NUL-termination, which is not strictly required\n";
            pr "   * but avoids a common bug in calling code.  Note that callers\n";
            pr "   * should NOT depend on this behaviour intentionally.\n";
            pr "   */\n";
            pr "  out->%s_len = inp->%s_len;\n" name name;
            pr "  out->%s = malloc (out->%s_len + 1);\n" name name;
            pr "  if (out->%s == NULL) goto error;\n" name;
            pr "  memcpy (out->%s, inp->%s, out->%s_len);\n" name name name;
            pr "  out->%s[out->%s_len] = '\\0';\n" name name
          | name, FUUID ->
            pr "  memcpy (out->%s, inp->%s, 32 * sizeof (char));\n" name name;
          | name, FChar
          | name, FUInt32
          | name, FInt32
          | name, FUInt64
          | name, FBytes
          | name, FInt64
          | name, FOptPercent ->
            pr "  out->%s = inp->%s;\n" name name;
        ) cols;
        pr "  return 0;\n";
        pr "\n";
        pr "error: ;\n";
        pr "  err = errno;\n";
        pr "  free_%s (out);\n" typ;
        pr "  errno = err;\n";
        pr "  return -1;\n";
        pr "}\n";
      )
      else (
        (* If a struct has no boxed columns, then we can just do a memcpy. *)
        pr "static void\n";
        pr "copy_%s (const struct guestfs_%s *inp, struct guestfs_%s *out)\n"
          typ typ typ;
        pr "{\n";
        pr "  memcpy (out, inp, sizeof *out);\n";
        pr "}\n";
      );

      pr "\n";
      pr "GUESTFS_DLL_PUBLIC struct guestfs_%s *\n" typ;
      pr "guestfs_copy_%s (const struct guestfs_%s *inp)\n" typ typ;
      pr "{\n";
      pr "  struct guestfs_%s *ret;\n" typ;
      pr "\n";
      pr "  ret = malloc (sizeof *ret);\n";
      pr "  if (ret == NULL)\n";
      pr "    return NULL;\n";
      pr "\n";
      if has_boxed_cols then (
        pr "  if (copy_%s (inp, ret) == -1) {\n" typ;
        pr "    int err;\n";
        pr "\n";
        pr "    err = errno;\n";
        pr "    free (ret);\n";
        pr "    errno = err;\n";
        pr "    return NULL;\n";
        pr "  }\n"
      ) else (
        pr "  copy_%s (inp, ret);\n" typ
      );
      pr "\n";
      pr "  return ret;\n";
      pr "}\n";

      pr "\n";
      pr "GUESTFS_DLL_PUBLIC struct guestfs_%s_list *\n" typ;
      pr "guestfs_copy_%s_list (const struct guestfs_%s_list *inp)\n" typ typ;
      pr "{\n";
      pr "  int err;\n";
      pr "  struct guestfs_%s_list *ret;\n" typ;
      pr "  size_t i = 0;\n";
      if has_boxed_cols then
        pr "  size_t j;\n";
      pr "\n";
      pr "  ret = malloc (sizeof *ret);\n";
      pr "  if (ret == NULL)\n";
      pr "    return NULL;\n";
      pr "\n";
      pr "  ret->len = inp->len;\n";
      pr "  ret->val = malloc (sizeof (struct guestfs_%s) * ret->len);\n" typ;
      pr "  if (ret->val == NULL)\n";
      pr "    goto error;\n";
      pr "\n";
      pr "  for (i = 0; i < ret->len; ++i) {\n";
      if has_boxed_cols then (
        pr "    if (copy_%s (&inp->val[i], &ret->val[i]) == -1)\n" typ;
        pr "      goto error;\n"
      ) else (
        pr "    copy_%s (&inp->val[i], &ret->val[i]);\n" typ
      );
      pr "  }\n";
      pr "\n";
      pr "  return ret;\n";
      pr "\n";
      pr "error: ;\n";
      pr "  err = errno;\n";
      if has_boxed_cols then (
        pr "  for (j = 0; j < i; ++j)\n";
        pr "    free_%s (&ret->val[j]);\n" typ
      );
      pr "  free (ret->val);\n";
      pr "  free (ret);\n";
      pr "  errno = err;\n";
      pr "  return NULL;\n";
      pr "}\n";
  ) structs

(* Functions to free structures used by the CLEANUP_* macros. *)
and generate_client_structs_cleanup () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>

#include \"guestfs.h\"
#include \"guestfs-internal-frontend.h\"

";

  pr "/* Cleanup functions used by CLEANUP_* macros.  Do not call\n";
  pr " * these functions directly.\n";
  pr " */\n";
  pr "\n";

  List.iter (
    fun { s_name = typ } ->
      pr "void\n";
      pr "guestfs_int_cleanup_free_%s (void *ptr)\n" typ;
      pr "{\n";
      pr "  guestfs_free_%s (* (struct guestfs_%s **) ptr);\n" typ typ;
      pr "}\n";
      pr "\n";

      pr "void\n";
      pr "guestfs_int_cleanup_free_%s_list (void *ptr)\n" typ;
      pr "{\n";
      pr "  guestfs_free_%s_list (* (struct guestfs_%s_list **) ptr);\n"
        typ typ;
      pr "}\n";
      pr "\n";

  ) structs

(* Generate structs-print.c file. *)
and generate_client_structs_print_c () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <config.h>

#include <inttypes.h>

#include \"c-ctype.h\"

#include \"guestfs.h\"
#include \"structs-print.h\"

";

  let write_structs =
    List.iter (
      fun { s_name = typ; s_cols = cols } ->
        let needs_i =
          List.exists (function (_, (FUUID|FBuffer)) -> true | _ -> false) cols in

        pr "void\n";
        pr "guestfs_int_print_%s_indent (struct guestfs_%s *%s, FILE *dest, const char *linesep, const char *indent)\n"
          typ typ typ;
        pr "{\n";
        if needs_i then (
          pr "  size_t i;\n";
          pr "\n"
        );
        List.iter (
          function
          | name, FString ->
              pr "  fprintf (dest, \"%%s%s: %%s%%s\", indent, %s->%s, linesep);\n"
                name typ name
          | name, FUUID ->
              pr "  fprintf (dest, \"%%s%s: \", indent);\n" name;
              pr "  for (i = 0; i < 32; ++i)\n";
              pr "    fprintf (dest, \"%%c\", %s->%s[i]);\n" typ name;
              pr "  fprintf (dest, \"%%s\", linesep);\n"
          | name, FBuffer ->
              pr "  fprintf (dest, \"%%s%s: \", indent);\n" name;
              pr "  for (i = 0; i < %s->%s_len; ++i)\n" typ name;
              pr "    if (c_isprint (%s->%s[i]))\n" typ name;
              pr "      fprintf (dest, \"%%c\", %s->%s[i]);\n" typ name;
              pr "    else\n";
              pr "      fprintf (dest, \"\\\\x%%02x\", (unsigned) %s->%s[i]);\n"
                 typ name;
              pr "  fprintf (dest, \"%%s\", linesep);\n"
          | name, (FUInt64|FBytes) ->
              pr "  fprintf (dest, \"%%s%s: %%\" PRIu64 \"%%s\", indent, %s->%s, linesep);\n"
                name typ name
          | name, FInt64 ->
              pr "  fprintf (dest, \"%%s%s: %%\" PRIi64 \"%%s\", indent, %s->%s, linesep);\n"
                name typ name
          | name, FUInt32 ->
              pr "  fprintf (dest, \"%%s%s: %%\" PRIu32 \"%%s\", indent, %s->%s, linesep);\n"
                name typ name
          | name, FInt32 ->
              pr "  fprintf (dest, \"%%s%s: %%\" PRIi32 \"%%s\", indent, %s->%s, linesep);\n"
                name typ name
          | name, FChar ->
              pr "  fprintf (dest, \"%%s%s: %%c%%s\", indent, %s->%s, linesep);\n"
                name typ name
          | name, FOptPercent ->
              pr "  if (%s->%s >= 0)\n" typ name;
              pr "    fprintf (dest, \"%%s%s: %%g %%%%%%s\", indent, (double) %s->%s, linesep);\n"
                name typ name;
              pr "  else\n";
              pr "    fprintf (dest, \"%%s%s: %%s\", indent, linesep);\n" name
        ) cols;
        pr "}\n";
        pr "\n";
    ) in

  write_structs external_structs;

  pr "\
#if GUESTFS_PRIVATE

";

  write_structs internal_structs;

  pr "\
#endif /* End of GUESTFS_PRIVATE. */
"

(* Generate structs-print.h file. *)
and generate_client_structs_print_h () =
  generate_header CStyle LGPLv2plus;

  pr "\
#ifndef GUESTFS_INTERNAL_STRUCTS_PRINT_H_
#define GUESTFS_INTERNAL_STRUCTS_PRINT_H_

#include <stdio.h>

";

  let write_structs =
    List.iter (
      fun { s_name = name } ->
        pr "extern void guestfs_int_print_%s_indent (struct guestfs_%s *%s, FILE *dest, const char *linesep, const char *indent);\n"
          name name name
    ) in

  write_structs external_structs;

  pr "\

#if GUESTFS_PRIVATE

";

  write_structs internal_structs;

  pr "\

#endif /* End of GUESTFS_PRIVATE. */

#endif /* GUESTFS_INTERNAL_STRUCTS_PRINT_H_ */
"

(* Generate the client-side dispatch stubs. *)
and generate_client_actions hash () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <string.h>

#include \"guestfs.h\"
#include \"guestfs-internal.h\"
#include \"guestfs-internal-actions.h\"
#include \"guestfs_protocol.h\"
#include \"errnostring.h\"
#include \"structs-print.h\"

";

  (* Generate code for enter events. *)
  let enter_event shortname =
    pr "  guestfs_int_call_callbacks_message (g, GUESTFS_EVENT_ENTER,\n";
    pr "                                      \"%s\", %d);\n"
      shortname (String.length shortname)
  in

  (* Generate code to check String-like parameters are not passed in
   * as NULL (returning an error if they are).
   *)
  let check_null_strings c_name (ret, args, optargs) =
    let pr_newline = ref false in
    List.iter (
      function
      (* parameters which should not be NULL *)
      | String n
      | Device n
      | Mountable n
      | Pathname n
      | Dev_or_Path n | Mountable_or_Path n
      | FileIn n
      | FileOut n
      | BufferIn n
      | StringList n
      | DeviceList n
      | Key n
      | Pointer (_, n)
      | GUID n
      | FilenameList n ->
          pr "  if (%s == NULL) {\n" n;
          pr "    error (g, \"%%s: %%s: parameter cannot be NULL\",\n";
          pr "           \"%s\", \"%s\");\n" c_name n;
          let errcode =
            match errcode_of_ret ret with
            | `CannotReturnError ->
                (* XXX hack *)
                if c_name = "internal_test_rconstoptstring" then
                  `ErrorIsNULL
                else
                  failwithf
                    "%s: RConstOptString function has invalid parameter '%s'"
                    c_name n
            | (`ErrorIsMinusOne |`ErrorIsNULL) as e -> e in
          pr "    return %s;\n" (string_of_errcode errcode);
          pr "  }\n";
          pr_newline := true

      (* can be NULL *)
      | OptString _

      (* not applicable *)
      | Bool _
      | Int _
      | Int64 _ -> ()
    ) args;

    (* For optional arguments. *)
    List.iter (
      function
      | OString n ->
          pr "  if ((optargs->bitmask & GUESTFS_%s_%s_BITMASK) &&\n"
            (String.uppercase c_name) (String.uppercase n);
          pr "      optargs->%s == NULL) {\n" n;
          pr "    error (g, \"%%s: %%s: optional parameter cannot be NULL\",\n";
          pr "           \"%s\", \"%s\");\n" c_name n;
          let errcode =
            match errcode_of_ret ret with
            | `CannotReturnError -> assert false
            | (`ErrorIsMinusOne |`ErrorIsNULL) as e -> e in
          pr "    return %s;\n" (string_of_errcode errcode);
          pr "  }\n";
          pr_newline := true

      | OStringList n ->
          pr "  if ((optargs->bitmask & GUESTFS_%s_%s_BITMASK) &&\n"
            (String.uppercase c_name) (String.uppercase n);
          pr "      optargs->%s == NULL) {\n" n;
          pr "    error (g, \"%%s: %%s: optional list cannot be NULL\",\n";
          pr "           \"%s\", \"%s\");\n" c_name n;
          let errcode =
            match errcode_of_ret ret with
            | `CannotReturnError -> assert false
            | (`ErrorIsMinusOne |`ErrorIsNULL) as e -> e in
          pr "    return %s;\n" (string_of_errcode errcode);
          pr "  }\n";
          pr_newline := true

      (* not applicable *)
      | OBool _ | OInt _ | OInt64 _ -> ()
    ) optargs;

    if !pr_newline then pr "\n";
  in

  (* Generate code to reject optargs we don't know about. *)
  let reject_unknown_optargs c_name = function
    | _, _, [] -> ()
    | ret, _, optargs ->
        let len = List.length optargs in
        let mask = Int64.lognot (Int64.pred (Int64.shift_left 1L len)) in
        pr "  if (optargs->bitmask & UINT64_C(0x%Lx)) {\n" mask;
        pr "    error (g, \"%%s: unknown option in guestfs_%%s_argv->bitmask (this can happen if a program is compiled against a newer version of libguestfs, then dynamically linked to an older version)\",\n";
        pr "           \"%s\", \"%s\");\n" c_name c_name;
        let errcode =
          match errcode_of_ret ret with
          | `CannotReturnError -> assert false
          | (`ErrorIsMinusOne |`ErrorIsNULL) as e -> e in
        pr "    return %s;\n" (string_of_errcode errcode);
        pr "  }\n";
        pr "\n";
  in

  (* Generate code to check for parameter validation (where supported
   * for the type).
   *)
  let check_args_validity c_name (ret, args, optargs) =
    let pr_newline = ref false in
    List.iter (
      function
      | GUID n ->
          pr "  if (!guestfs_int_validate_guid (%s)) {\n" n;
          pr "    error (g, \"%%s: %%s: parameter is not a valid GUID\",\n";
          pr "           \"%s\", \"%s\");\n" c_name n;
          let errcode =
            match errcode_of_ret ret with
            | `CannotReturnError -> assert false
            | (`ErrorIsMinusOne |`ErrorIsNULL) as e -> e in
          pr "    return %s;\n" (string_of_errcode errcode);
          pr "  }\n";
          pr_newline := true

      | FilenameList n ->
          pr "  {\n";
          pr "    size_t i;\n";
          pr "    for (i = 0; %s[i] != NULL; ++i) {\n" n;
          pr "      if (strchr (%s[i], '/') != NULL) {\n" n;
          pr "        error (g, \"%%s: %%s: '%%s' is not a file name\",\n";
          pr "               \"%s\", \"%s\", %s[i]);\n" c_name n n;
          let errcode =
            match errcode_of_ret ret with
            | `CannotReturnError -> assert false
            | (`ErrorIsMinusOne |`ErrorIsNULL) as e -> e in
          pr "        return %s;\n" (string_of_errcode errcode);
          pr "      }\n";
          pr "    }\n";
          pr "  }\n";
          pr_newline := true

      (* not applicable *)
      | String _
      | Device _
      | Mountable _
      | Pathname _
      | Dev_or_Path _ | Mountable_or_Path _
      | FileIn _
      | FileOut _
      | BufferIn _
      | StringList _
      | DeviceList _
      | Key _
      | Pointer (_, _)
      | OptString _
      | Bool _
      | Int _
      | Int64 _ -> ()
    ) args;

    if !pr_newline then pr "\n";
  in

  (* Generate code to generate guestfish call traces. *)
  let trace_call name c_name (ret, args, optargs) =
    pr "  if (trace_flag) {\n";

    let needs_i =
      List.exists (function
      | StringList _ | DeviceList _ | FilenameList _ -> true
      | _ -> false) args ||
      List.exists (function
      | OStringList _ -> true
      | _ -> false) optargs in
    if needs_i then (
      pr "    size_t i;\n";
      pr "\n"
    );

    pr "    guestfs_int_trace_open (&trace_buffer);\n";

    pr "    fprintf (trace_buffer.fp, \"%%s\", \"%s\");\n" name;

    (* Required arguments. *)
    List.iter (
      function
      | String n			(* strings *)
      | Device n
      | Mountable n
      | Pathname n
      | Dev_or_Path n | Mountable_or_Path n
      | FileIn n
      | FileOut n
      | GUID n ->
          (* guestfish doesn't support string escaping, so neither do we *)
          pr "    fprintf (trace_buffer.fp, \" \\\"%%s\\\"\", %s);\n" n
      | Key n ->
          (* don't print keys *)
          pr "    fprintf (trace_buffer.fp, \" \\\"***\\\"\");\n"
      | OptString n ->			(* string option *)
          pr "    if (%s)\n" n;
          pr "      fprintf (trace_buffer.fp, \" \\\"%%s\\\"\", %s);\n" n;
          pr "    else\n";
          pr "      fprintf (trace_buffer.fp, \" null\");\n"
      | StringList n
      | DeviceList n
      | FilenameList n ->			(* string list *)
          pr "    fputc (' ', trace_buffer.fp);\n";
          pr "    fputc ('\"', trace_buffer.fp);\n";
          pr "    for (i = 0; %s[i]; ++i) {\n" n;
          pr "      if (i > 0) fputc (' ', trace_buffer.fp);\n";
          pr "      fputs (%s[i], trace_buffer.fp);\n" n;
          pr "    }\n";
          pr "    fputc ('\"', trace_buffer.fp);\n";
      | Bool n ->			(* boolean *)
          pr "    fputs (%s ? \" true\" : \" false\", trace_buffer.fp);\n" n
      | Int n ->			(* int *)
          pr "    fprintf (trace_buffer.fp, \" %%d\", %s);\n" n
      | Int64 n ->
          pr "    fprintf (trace_buffer.fp, \" %%\" PRIi64, %s);\n" n
      | BufferIn n ->                   (* RHBZ#646822 *)
          pr "    fputc (' ', trace_buffer.fp);\n";
          pr "    guestfs_int_print_BufferIn (trace_buffer.fp, %s, %s_size);\n" n n
      | Pointer (t, n) ->
          pr "    fprintf (trace_buffer.fp, \" (%s)%%p\", %s);\n" t n
    ) args;

    (* Optional arguments. *)
    List.iter (
      fun argt ->
        let n = name_of_optargt argt in
        pr "    if (optargs->bitmask & GUESTFS_%s_%s_BITMASK) {\n"
          (String.uppercase c_name) (String.uppercase n);
        (match argt with
         | OString n ->
             pr "      fprintf (trace_buffer.fp, \" \\\"%%s:%%s\\\"\", \"%s\", optargs->%s);\n" n n
         | OStringList n ->
             pr "      fprintf (trace_buffer.fp, \" \\\"%%s:\", \"%s\");\n" n;
             pr "      for (i = 0; optargs->%s[i] != NULL; ++i) {\n" n;
             pr "        if (i > 0) fputc (' ', trace_buffer.fp);\n";
             pr "        fputs (optargs->%s[i], trace_buffer.fp);\n" n;
             pr "      }\n";
             pr "      fputc ('\\\"', trace_buffer.fp);\n"
         | OBool n ->
             pr "      fprintf (trace_buffer.fp, \" \\\"%%s:%%s\\\"\", \"%s\", optargs->%s ? \"true\" : \"false\");\n" n n
         | OInt n ->
             pr "      fprintf (trace_buffer.fp, \" \\\"%%s:%%d\\\"\", \"%s\", optargs->%s);\n" n n
         | OInt64 n ->
             pr "      fprintf (trace_buffer.fp, \" \\\"%%s:%%\" PRIi64 \"\\\"\", \"%s\", optargs->%s);\n" n n
        );
        pr "    }\n"
    ) optargs;

    pr "    guestfs_int_trace_send_line (g, &trace_buffer);\n";
    pr "  }\n";
    pr "\n";
  in

  let trace_return ?(indent = 2) name (ret, _, _) rv =
    let indent = spaces indent in

    pr "%sif (trace_flag) {\n" indent;

    let needs_i =
      match ret with
      | RStringList _ | RHashtable _ | RStructList _ -> true
      | _ -> false in
    if needs_i then (
      pr "%s  size_t i;\n" indent;
      pr "\n"
    );

    pr "%s  guestfs_int_trace_open (&trace_buffer);\n" indent;

    pr "%s  fprintf (trace_buffer.fp, \"%%s = \", \"%s\");\n" indent name;

    (match ret with
     | RErr | RInt _ | RBool _ ->
         pr "%s  fprintf (trace_buffer.fp, \"%%d\", %s);\n" indent rv
     | RInt64 _ ->
         pr "%s  fprintf (trace_buffer.fp, \"%%\" PRIi64, %s);\n" indent rv
     | RConstString _ | RString _ ->
         pr "%s  fprintf (trace_buffer.fp, \"\\\"%%s\\\"\", %s);\n" indent rv
     | RConstOptString _ ->
         pr "%s  fprintf (trace_buffer.fp, \"\\\"%%s\\\"\", %s != NULL ? %s : \"NULL\");\n"
           indent rv rv
     | RBufferOut _ ->
         pr "%s  guestfs_int_print_BufferOut (trace_buffer.fp, %s, *size_r);\n" indent rv
     | RStringList _ | RHashtable _ ->
         pr "%s  fputs (\"[\", trace_buffer.fp);\n" indent;
         pr "%s  for (i = 0; %s[i]; ++i) {\n" indent rv;
         pr "%s    if (i > 0) fputs (\", \", trace_buffer.fp);\n" indent;
         pr "%s    fputs (\"\\\"\", trace_buffer.fp);\n" indent;
         pr "%s    fputs (%s[i], trace_buffer.fp);\n" indent rv;
         pr "%s    fputs (\"\\\"\", trace_buffer.fp);\n" indent;
         pr "%s  }\n" indent;
         pr "%s  fputs (\"]\", trace_buffer.fp);\n" indent;
     | RStruct (_, typ) ->
         pr "%s  fprintf (trace_buffer.fp, \"<struct guestfs_%s = \");\n"
           indent typ;
         pr "%s  guestfs_int_print_%s_indent (%s, trace_buffer.fp, \", \", \"\");\n"
           indent typ rv;
         pr "%s  fprintf (trace_buffer.fp, \">\");\n" indent
     | RStructList (_, typ) ->
         pr "%s  fprintf (trace_buffer.fp, \"<struct guestfs_%s_list(%%u)\", %s->len);\n"
           indent typ rv;
         pr "%s  if (%s->len > 0)\n" indent rv;
         pr "%s    fprintf (trace_buffer.fp, \" = \");\n" indent;
         pr "%s  for (i = 0; i < %s->len; ++i) {\n" indent rv;
         pr "%s    if (i != 0)\n" indent;
         pr "%s      fprintf (trace_buffer.fp, \" \");\n" indent;
         pr "%s    fprintf (trace_buffer.fp, \"[%%zu]{\", i);\n" indent;
         pr "%s    guestfs_int_print_%s_indent (&%s->val[i], trace_buffer.fp, \", \", \"\");\n"
           indent typ rv;
         pr "%s    fprintf (trace_buffer.fp, \"}\");\n" indent;
         pr "%s  }\n" indent;
         pr "%s  fprintf (trace_buffer.fp, \">\");\n" indent
    );
    pr "%s  guestfs_int_trace_send_line (g, &trace_buffer);\n" indent;
    pr "%s}\n" indent;
    pr "\n";
  in

  let trace_return_error ?(indent = 2) name (ret, _, _) errcode =
    let indent = spaces indent in

    pr "%sif (trace_flag)\n" indent;

    pr "%s  guestfs_int_trace (g, \"%%s = %%s (error)\",\n" indent;
    pr "%s                     \"%s\", \"%s\");\n"
      indent name (string_of_errcode errcode)
  in

  let handle_null_optargs optargs c_name =
    if optargs <> [] then (
      pr "  struct guestfs_%s_argv optargs_null;\n" c_name;
      pr "  if (!optargs) {\n";
      pr "    optargs_null.bitmask = 0;\n";
      pr "    optargs = &optargs_null;\n";
      pr "  }\n\n";
    )
  in

  (* For non-daemon functions, generate a wrapper around each function. *)
  let generate_non_daemon_wrapper { name = name; c_name = c_name;
                                    style = ret, _, optargs as style;
                                    config_only = config_only } =
    if optargs = [] then
      generate_prototype ~extern:false ~semicolon:false ~newline:true
        ~handle:"g" ~prefix:"guestfs_"
        ~dll_public:true
        c_name style
    else
      generate_prototype ~extern:false ~semicolon:false ~newline:true
        ~handle:"g" ~prefix:"guestfs_" ~suffix:"_argv" ~optarg_proto:Argv
        ~dll_public:true
        c_name style;
    pr "{\n";

    handle_null_optargs optargs c_name;

    pr "  int trace_flag = g->trace;\n";
    pr "  struct trace_buffer trace_buffer;\n";
    (match ret with
    | RErr | RInt _ | RBool _ ->
      pr "  int r;\n"
    | RInt64 _ ->
      pr "  int64_t r;\n"
    | RConstString _ ->
      pr "  const char *r;\n"
    | RConstOptString _ ->
      pr "  const char *r;\n"
    | RString _ | RBufferOut _ ->
      pr "  char *r;\n"
    | RStringList _ | RHashtable _ ->
      pr "  char **r;\n"
    | RStruct (_, typ) ->
      pr "  struct guestfs_%s *r;\n" typ
    | RStructList (_, typ) ->
      pr "  struct guestfs_%s_list *r;\n" typ
    );
    pr "\n";
    if config_only then (
      pr "  if (g->state != CONFIG) {\n";
      pr "    error (g, \"%%s: this function can only be called in the config state\",\n";
      pr "              \"%s\");\n" c_name;
      pr "    return -1;\n";
      pr "  }\n";
    );
    enter_event name;
    check_null_strings c_name style;
    reject_unknown_optargs c_name style;
    check_args_validity c_name style;
    trace_call name c_name style;
    pr "  r = guestfs_impl_%s " c_name;
    generate_c_call_args ~handle:"g" ~implicit_size_ptr:"size_r" style;
    pr ";\n";
    pr "\n";
    (match errcode_of_ret ret with
    | (`ErrorIsMinusOne | `ErrorIsNULL) as errcode ->
      pr "  if (r != %s) {\n" (string_of_errcode errcode);
      trace_return ~indent:4 name style "r";
      pr "  } else {\n";
      trace_return_error ~indent:4 name style errcode;
      pr "  }\n";
    | `CannotReturnError ->
      trace_return name style "r";
    );
    pr "\n";
    pr "  return r;\n";
    pr "}\n";
    pr "\n"
  in

  List.iter (
    function
    | { wrapper = true } as f ->
      if hash_matches hash f then generate_non_daemon_wrapper f
    | { wrapper = false } ->
      () (* no wrapper *)
  ) non_daemon_functions;

  (* Client-side stubs for each function. *)
  let generate_daemon_stub { name = name; c_name = c_name;
                             style = ret, args, optargs as style } =
    let errcode =
      match errcode_of_ret ret with
      | `CannotReturnError -> assert false
      | (`ErrorIsMinusOne | `ErrorIsNULL) as e -> e in

    (* Generate the action stub. *)
    if optargs = [] then
      generate_prototype ~extern:false ~semicolon:false ~newline:true
        ~handle:"g" ~prefix:"guestfs_"
        ~dll_public:true
        c_name style
    else
      generate_prototype ~extern:false ~semicolon:false ~newline:true
        ~handle:"g" ~prefix:"guestfs_" ~suffix:"_argv"
        ~optarg_proto:Argv
        ~dll_public:true
        c_name style;

    pr "{\n";

    handle_null_optargs optargs c_name;

    let args_passed_to_daemon =
      List.filter (function FileIn _ | FileOut _ -> false | _ -> true)
        args in
    (match args_passed_to_daemon, optargs with
    | [], [] -> ()
    | _, _ -> pr "  struct guestfs_%s_args args;\n" name
    );

    pr "  guestfs_message_header hdr;\n";
    pr "  guestfs_message_error err;\n";
    let has_ret =
      match ret with
      | RErr -> false
      | RConstString _ | RConstOptString _ ->
        failwithf "RConstString|RConstOptString cannot be used by daemon functions"
      | RInt _ | RInt64 _
      | RBool _ | RString _ | RStringList _
      | RStruct _ | RStructList _
      | RHashtable _ | RBufferOut _ ->
        pr "  struct guestfs_%s_ret ret;\n" name;
        true in

    pr "  int serial;\n";
    pr "  int r;\n";
    pr "  int trace_flag = g->trace;\n";
    pr "  struct trace_buffer trace_buffer;\n";
    (match ret with
    | RErr | RInt _ | RBool _ -> pr "  int ret_v;\n"
    | RInt64 _ -> pr "  int64_t ret_v;\n"
    | RConstString _ | RConstOptString _ -> pr "  const char *ret_v;\n"
    | RString _ | RBufferOut _ -> pr "  char *ret_v;\n"
    | RStringList _ | RHashtable _ -> pr "  char **ret_v;\n"
    | RStruct (_, typ) -> pr "  struct guestfs_%s *ret_v;\n" typ
    | RStructList (_, typ) -> pr "  struct guestfs_%s_list *ret_v;\n" typ
    );

    let has_filein =
      List.exists (function FileIn _ -> true | _ -> false) args in
    if has_filein then (
      pr "  uint64_t progress_hint = 0;\n";
      pr "  struct stat progress_stat;\n";
    ) else
      pr "  const uint64_t progress_hint = 0;\n";

    pr "\n";

    enter_event name;
    check_null_strings c_name style;
    reject_unknown_optargs c_name style;
    check_args_validity c_name style;
    trace_call name c_name style;

    (* RHEL 7 *)
    if name = "mount" || name = "mount_ro" || name = "mount_options" ||
       name = "mount_vfs" then (
      pr "  if (g->program && !STRPREFIX (g->program, \"virt-\")) {\n";
      pr "    CLEANUP_FREE char *vfs_type = guestfs_vfs_type (g, mountable);\n";
      pr "    if (vfs_type && STREQ (vfs_type, \"ntfs\")) {\n";
      pr "      error (g, \"mount: unsupported filesystem type\");\n";
      pr "      if (trace_flag)\n";
      pr "        guestfs_int_trace (g, \"%%s = %%s (error)\",\n";
      pr "                              \"%s\", \"-1\");\n" name;
      pr "      return %s;\n" (string_of_errcode errcode);
      pr "    }\n";
      pr "  }\n";
      pr "\n";
    );

    (* Calculate the total size of all FileIn arguments to pass
     * as a progress bar hint.
     *)
    List.iter (
      function
      | FileIn n ->
        pr "  if (stat (%s, &progress_stat) == 0 &&\n" n;
        pr "      S_ISREG (progress_stat.st_mode))\n";
        pr "    progress_hint += progress_stat.st_size;\n";
        pr "\n";
      | _ -> ()
    ) args;

    (* This is a daemon_function so check the appliance is up. *)
    pr "  if (guestfs_int_check_appliance_up (g, \"%s\") == -1) {\n" name;
    trace_return_error ~indent:4 name style errcode;
    pr "    return %s;\n" (string_of_errcode errcode);
    pr "  }\n";
    pr "\n";

    (* Send the main header and arguments. *)
    if args_passed_to_daemon = [] && optargs = [] then (
      pr "  serial = guestfs_int_send (g, GUESTFS_PROC_%s, progress_hint, 0,\n"
        (String.uppercase name);
      pr "                             NULL, NULL);\n"
    ) else (
      List.iter (
        function
        | Pathname n | Device n | Mountable n | Dev_or_Path n 
        | Mountable_or_Path n | String n
        | Key n | GUID n ->
          pr "  args.%s = (char *) %s;\n" n n
        | OptString n ->
          pr "  args.%s = %s ? (char **) &%s : NULL;\n" n n n
        | StringList n | DeviceList n | FilenameList n ->
          pr "  args.%s.%s_val = (char **) %s;\n" n n n;
          pr "  for (args.%s.%s_len = 0; %s[args.%s.%s_len]; args.%s.%s_len++) ;\n" n n n n n n n;
        | Bool n ->
          pr "  args.%s = %s;\n" n n
        | Int n ->
          pr "  args.%s = %s;\n" n n
        | Int64 n ->
          pr "  args.%s = %s;\n" n n
        | BufferIn n ->
          pr "  /* Just catch grossly large sizes. XDR encoding will make this precise. */\n";
          pr "  if (%s_size >= GUESTFS_MESSAGE_MAX) {\n" n;
          trace_return_error ~indent:4 name style errcode;
          pr "    error (g, \"%%s: size of input buffer too large\", \"%s\");\n"
            name;
          pr "    return %s;\n" (string_of_errcode errcode);
          pr "  }\n";
          pr "  args.%s.%s_val = (char *) %s;\n" n n n;
          pr "  args.%s.%s_len = %s_size;\n" n n n
        | FileIn _ | FileOut _ | Pointer _ -> assert false
      ) args_passed_to_daemon;

      List.iter (
        fun argt ->
          let n = name_of_optargt argt in
          pr "  if (optargs->bitmask & GUESTFS_%s_%s_BITMASK) {\n"
            (String.uppercase c_name) (String.uppercase n);
          (match argt with
          | OBool n
          | OInt n
          | OInt64 n ->
            pr "    args.%s = optargs->%s;\n" n n;
            pr "  } else {\n";
            pr "    args.%s = 0;\n" n;
            pr "  }\n";
          | OString n ->
            pr "    args.%s = (char *) optargs->%s;\n" n n;
            pr "  } else {\n";
            pr "    args.%s = (char *) \"\";\n" n;
            pr "  }\n";
          | OStringList n ->
            pr "    args.%s.%s_val = (char **) optargs->%s;\n" n n n;
            pr "    for (args.%s.%s_len = 0; optargs->%s[args.%s.%s_len]; args.%s.%s_len++) ;\n" n n n n n n n;
            pr "  } else {\n";
            pr "    args.%s.%s_len = 0;\n" n n;
            pr "    args.%s.%s_val = NULL;\n" n n;
            pr "  }\n";
          )
      ) optargs;

      pr "  serial = guestfs_int_send (g, GUESTFS_PROC_%s,\n"
        (String.uppercase name);
      pr "                             progress_hint, %s,\n"
        (if optargs <> [] then "optargs->bitmask" else "0");
      pr "                             (xdrproc_t) xdr_guestfs_%s_args, (char *) &args);\n"
        name;
    );
    pr "  if (serial == -1) {\n";
    trace_return_error ~indent:4 name style errcode;
    pr "    return %s;\n" (string_of_errcode errcode);
    pr "  }\n";
    pr "\n";

    (* Send any additional files (FileIn) requested. *)
    let need_read_reply_label = ref false in
    List.iter (
      function
      | FileIn n ->
        pr "  r = guestfs_int_send_file (g, %s);\n" n;
        pr "  if (r == -1) {\n";
        trace_return_error ~indent:4 name style errcode;
        pr "    /* daemon will send an error reply which we discard */\n";
        pr "    guestfs_int_recv_discard (g, \"%s\");\n" name;
        pr "    return %s;\n" (string_of_errcode errcode);
        pr "  }\n";
        pr "  if (r == -2) /* daemon cancelled */\n";
        pr "    goto read_reply;\n";
        need_read_reply_label := true;
        pr "\n";
      | _ -> ()
    ) args;

    (* Wait for the reply from the remote end. *)
    if !need_read_reply_label then pr " read_reply:\n";
    pr "  memset (&hdr, 0, sizeof hdr);\n";
    pr "  memset (&err, 0, sizeof err);\n";
    if has_ret then pr "  memset (&ret, 0, sizeof ret);\n";
    pr "\n";
    pr "  r = guestfs_int_recv (g, \"%s\", &hdr, &err,\n        " name;
    if not has_ret then
      pr "NULL, NULL"
    else
      pr "(xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret" name;
    pr ");\n";

    pr "  if (r == -1) {\n";
    trace_return_error ~indent:4 name style errcode;
    pr "    return %s;\n" (string_of_errcode errcode);
    pr "  }\n";
    pr "\n";

    pr "  if (guestfs_int_check_reply_header (g, &hdr, GUESTFS_PROC_%s, serial) == -1) {\n"
      (String.uppercase name);
    trace_return_error ~indent:4 name style errcode;
    pr "    return %s;\n" (string_of_errcode errcode);
    pr "  }\n";
    pr "\n";

    pr "  if (hdr.status == GUESTFS_STATUS_ERROR) {\n";
    pr "    int errnum = 0;\n";
    pr "\n";
    trace_return_error ~indent:4 name style errcode;
    pr "    if (err.errno_string[0] != '\\0')\n";
    pr "      errnum = guestfs_int_string_to_errno (err.errno_string);\n";
    pr "    if (errnum <= 0)\n";
    pr "      error (g, \"%%s: %%s\", \"%s\", err.error_message);\n"
      name;
    pr "    else\n";
    pr "      guestfs_int_error_errno (g, errnum, \"%%s: %%s\", \"%s\",\n"
      name;
    pr "                               err.error_message);\n";
    pr "    free (err.error_message);\n";
    pr "    free (err.errno_string);\n";
    pr "    return %s;\n" (string_of_errcode errcode);
    pr "  }\n";
    pr "\n";

    (* Expecting to receive further files (FileOut)? *)
    List.iter (
      function
      | FileOut n ->
        pr "  if (guestfs_int_recv_file (g, %s) == -1) {\n" n;
        trace_return_error ~indent:4 name style errcode;
        pr "    return %s;\n" (string_of_errcode errcode);
        pr "  }\n";
        pr "\n";
      | _ -> ()
    ) args;

    (match ret with
    | RErr ->
      pr "  ret_v = 0;\n"
    | RInt n | RInt64 n | RBool n ->
      pr "  ret_v = ret.%s;\n" n
    | RConstString _ | RConstOptString _ ->
      failwithf "RConstString|RConstOptString cannot be used by daemon functions"
    | RString n ->
      pr "  ret_v = ret.%s; /* caller will free */\n" n
    | RStringList n | RHashtable n ->
      pr "  /* caller will free this, but we need to add a NULL entry */\n";
      pr "  ret.%s.%s_val =\n" n n;
      pr "    safe_realloc (g, ret.%s.%s_val,\n" n n;
      pr "                  sizeof (char *) * (ret.%s.%s_len + 1));\n"
        n n;
      pr "  ret.%s.%s_val[ret.%s.%s_len] = NULL;\n" n n n n;
      pr "  ret_v = ret.%s.%s_val;\n" n n
    | RStruct (n, _) ->
      pr "  /* caller will free this */\n";
      pr "  ret_v = safe_memdup (g, &ret.%s, sizeof (ret.%s));\n" n n
    | RStructList (n, _) ->
      pr "  /* caller will free this */\n";
      pr "  ret_v = safe_memdup (g, &ret.%s, sizeof (ret.%s));\n" n n
    | RBufferOut n ->
      pr "  /* RBufferOut is tricky: If the buffer is zero-length, then\n";
      pr "   * _val might be NULL here.  To make the API saner for\n";
      pr "   * callers, we turn this case into a unique pointer (using\n";
      pr "   * malloc(1)).\n";
      pr "   */\n";
      pr "  if (ret.%s.%s_len > 0) {\n" n n;
      pr "    *size_r = ret.%s.%s_len;\n" n n;
      pr "    ret_v = ret.%s.%s_val; /* caller will free */\n" n n;
      pr "  } else {\n";
      pr "    free (ret.%s.%s_val);\n" n n;
      pr "    char *p = safe_malloc (g, 1);\n";
      pr "    *size_r = ret.%s.%s_len;\n" n n;
      pr "    ret_v = p;\n";
      pr "  }\n";
    );
    trace_return name style "ret_v";
    pr "  return ret_v;\n";
    pr "}\n\n"
  in

  List.iter (
    fun f ->
      if hash_matches hash f then generate_daemon_stub f
  ) daemon_functions

(* Functions which have optional arguments have two or three
 * generated variants.
 *)
and generate_client_actions_variants () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <inttypes.h>

#include \"guestfs.h\"
#include \"guestfs-internal.h\"
#include \"guestfs-internal-actions.h\"

";

  let generate_va_variants { name = name; c_name = c_name;
                             style = ret, args, optargs as style } =
    assert (optargs <> []); (* checked by caller *)

    (* Get the name of the last regular argument. *)
    let last_arg =
      match ret with
      | RBufferOut _ -> "size_r"
      | _ ->
        match args with
        | [] -> "g"
        | args ->
          let last = List.hd (List.rev args) in
          let name = name_of_argt last in
          match last with
          | BufferIn n -> name ^ "_size"
          | _ -> name
    in

    let rtype =
      match ret with
      | RErr | RInt _ | RBool _ -> "int "
      | RInt64 _ -> "int64_t "
      | RConstString _ | RConstOptString _ -> "const char *"
      | RString _ | RBufferOut _ -> "char *"
      | RStringList _ | RHashtable _ -> "char **"
      | RStruct (_, typ) -> sprintf "struct guestfs_%s *" typ
      | RStructList (_, typ) ->
        sprintf "struct guestfs_%s_list *" typ in

    (* The regular variable args function, just calls the _va variant. *)
    generate_prototype ~extern:false ~semicolon:false ~newline:true
      ~handle:"g" ~prefix:"guestfs_" c_name style;
    pr "{\n";
    pr "  va_list optargs;\n";
    pr "\n";
    pr "  %sr;\n" rtype;
    pr "\n";
    pr "  va_start (optargs, %s);\n" last_arg;
    pr "  r = guestfs_%s_va " c_name;
    generate_c_call_args ~handle:"g" ~implicit_size_ptr:"size_r" style;
    pr ";\n";
    pr "  va_end (optargs);\n";
    pr "\n";
    pr "  return r;\n";
    pr "}\n\n";

    generate_prototype ~extern:false ~semicolon:false ~newline:true
      ~handle:"g" ~prefix:"guestfs_" ~suffix:"_va" ~optarg_proto:VA
      c_name style;
    pr "{\n";
    pr "  struct guestfs_%s_argv optargs_s;\n" c_name;
    pr "  struct guestfs_%s_argv *optargs = &optargs_s;\n" c_name;
    pr "  int i;\n";
    pr "  uint64_t i_mask;\n";
    pr "\n";
    pr "  optargs_s.bitmask = 0;\n";
    pr "\n";
    pr "  while ((i = va_arg (args, int)) >= 0) {\n";
    pr "    switch (i) {\n";

    List.iter (
      fun argt ->
        let n = name_of_optargt argt in
        pr "    case GUESTFS_%s_%s:\n"
          (String.uppercase c_name) (String.uppercase n);
        pr "      optargs_s.%s = va_arg (args, " n;
        (match argt with
        | OBool _ | OInt _ -> pr "int"
        | OInt64 _ -> pr "int64_t"
        | OString _ -> pr "const char *"
        | OStringList _ -> pr "char *const *"
        );
        pr ");\n";
        pr "      break;\n";
    ) optargs;

    let errcode =
      match errcode_of_ret ret with
      | `CannotReturnError -> assert false
      | (`ErrorIsMinusOne | `ErrorIsNULL) as e -> e in

    pr "    default:\n";
    pr "      error (g, \"%%s: unknown option %%d (this can happen if a program is compiled against a newer version of libguestfs, then dynamically linked to an older version)\",\n";
    pr "             \"%s\", i);\n" name;
    pr "      return %s;\n" (string_of_errcode errcode);
    pr "    }\n";
    pr "\n";
    pr "    i_mask = UINT64_C(1) << i;\n";
    pr "    if (optargs_s.bitmask & i_mask) {\n";
    pr "      error (g, \"%%s: same optional argument specified more than once\",\n";
    pr "             \"%s\");\n" name;
    pr "      return %s;\n" (string_of_errcode errcode);
    pr "    }\n";
    pr "    optargs_s.bitmask |= i_mask;\n";
    pr "  }\n";
    pr "\n";
    pr "  return guestfs_%s_argv " c_name;
    generate_c_call_args ~handle:"g" ~implicit_size_ptr:"size_r" style;
    pr ";\n";
    pr "}\n\n"

  and generate_back_compat_wrapper { name = name;
                                     style = ret, args, _ as style } =
    generate_prototype ~extern:false ~semicolon:false ~newline:true
      ~handle:"g" ~prefix:"guestfs_"
      name (ret, args, []);
    pr "{\n";
    pr "  struct guestfs_%s_opts_argv optargs_s = { .bitmask = 0 };\n" name;
    pr "  struct guestfs_%s_opts_argv *optargs = &optargs_s;\n" name;
    pr "\n";
    pr "  return guestfs_%s_opts_argv " name;
    generate_c_call_args ~handle:"g" ~implicit_size_ptr:"size_r" style;
    pr ";\n";
    pr "}\n";
    pr "\n"
  in

  List.iter (
    function
    | { style = _, _, [] } -> ()
    | ({ style = _, _, (_::_); once_had_no_optargs = false } as f) ->
      generate_va_variants f
    | ({ style = _, _, (_::_); once_had_no_optargs = true } as f) ->
      generate_va_variants f;
      generate_back_compat_wrapper f
  ) all_functions_sorted

(* Code for turning events and event bitmasks into printable strings. *)
and generate_event_string_c () =
  generate_header CStyle LGPLv2plus;

  (* Longest event name. *)
  let longest = List.fold_left (
    fun longest (name, _) ->
      let len = String.length name in
      if len > longest then len else longest
  ) 0 events in

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libintl.h>

#include \"guestfs.h\"
#include \"guestfs-internal.h\"

GUESTFS_DLL_PUBLIC char *
guestfs_event_to_string (uint64_t event)
{
  char *ret;
  uint64_t i;
  size_t len;

  /* Count how long the final string will be. */
  len = 1;
  for (i = 0; i < %d; ++i) {
    if ((event & (UINT64_C(1) << i)) != 0)
      len += %d; /* overestimate */
  }

  /* Allocate the final string and construct it. */
  ret = malloc (len);
  if (!ret)
    return NULL;

  len = 0;

" (List.length events) (longest + 1);

  (* Sort the events alphabetically so the events are returned sorted. *)
  let sorted_event_names = List.sort compare (List.map fst events) in

  List.iter (
    fun name ->
      pr "  if ((event & GUESTFS_EVENT_%s) != 0) {\n" (String.uppercase name);
      pr "    strcpy (&ret[len], \"%s,\");\n" name;
      pr "    len += %d + 1;\n" (String.length name);
      pr "  }\n";
  ) sorted_event_names;

  pr "
  if (len > 0)
    ret[len-1] = '\\0'; /* truncates the final trailing comma */
  else
    ret[0] = '\\0';

  return ret;
}
"

(* Generate the linker script which controls the visibility of
 * symbols in the public ABI and ensures no other symbols get
 * exported accidentally.
 *)
and generate_linker_script () =
  generate_header HashStyle GPLv2plus;

  let globals = [
    "guestfs_create";
    "guestfs_create_flags";
    "guestfs_close";
    "guestfs_delete_event_callback";
    "guestfs_event_to_string";
    "guestfs_first_private";
    "guestfs_get_error_handler";
    "guestfs_get_out_of_memory_handler";
    "guestfs_get_private";
    "guestfs_last_errno";
    "guestfs_last_error";
    "guestfs_next_private";
    "guestfs_pop_error_handler";
    "guestfs_push_error_handler";
    "guestfs_set_close_callback";
    "guestfs_set_error_handler";
    "guestfs_set_event_callback";
    "guestfs_set_launch_done_callback";
    "guestfs_set_log_message_callback";
    "guestfs_set_out_of_memory_handler";
    "guestfs_set_private";
    "guestfs_set_progress_callback";
    "guestfs_set_subprocess_quit_callback";

    (* Unofficial parts of the API: the bindings code use these
     * functions, so it is useful to export them.
     *)
    "guestfs_int_safe_calloc";
    "guestfs_int_safe_malloc";
    "guestfs_int_safe_strdup";
    "guestfs_int_safe_memdup";
  ] in
  let functions =
    List.flatten (
      List.map (
        function
        | { c_name = c_name; style = _, _, [] } -> ["guestfs_" ^ c_name]
        | { c_name = c_name; style = _, _, (_::_);
            once_had_no_optargs = false } ->
            ["guestfs_" ^ c_name;
             "guestfs_" ^ c_name ^ "_va";
             "guestfs_" ^ c_name ^ "_argv"]
        | { name = name; c_name = c_name; style = _, _, (_::_);
            once_had_no_optargs = true } ->
            ["guestfs_" ^ name;
             "guestfs_" ^ c_name;
             "guestfs_" ^ c_name ^ "_va";
             "guestfs_" ^ c_name ^ "_argv"]
      ) all_functions
    ) in
  let struct_frees =
    List.concat (
      List.map (fun { s_name = typ } ->
        ["guestfs_compare_" ^ typ;
         "guestfs_compare_" ^ typ ^ "_list";
         "guestfs_copy_" ^ typ;
         "guestfs_copy_" ^ typ ^ "_list";
         "guestfs_free_" ^ typ;
         "guestfs_free_" ^ typ ^ "_list"]
      ) structs
    ) in
  let globals = List.sort compare (globals @
                                     functions @
                                     struct_frees) in

  pr "{\n";
  pr "    global:\n";
  List.iter (pr "        %s;\n") globals;
  pr "\n";

  pr "    local:\n";
  pr "        *;\n";
  pr "};\n"

and generate_max_proc_nr () =
  pr "%d\n" max_proc_nr
