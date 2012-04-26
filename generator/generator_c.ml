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
open Generator_api_versions
open Generator_optgroups
open Generator_actions
open Generator_structs
open Generator_events

(* Generate C API. *)

type optarg_proto = Dots | VA | Argv

(* Generate a C function prototype. *)
let rec generate_prototype ?(extern = true) ?(static = false)
    ?(semicolon = true)
    ?(single_line = false) ?(indent = "") ?(newline = false)
    ?(in_daemon = false)
    ?(dll_public = false)
    ?(prefix = "") ?(suffix = "")
    ?handle
    ?(optarg_proto = Dots)
    name (ret, args, optargs) =
  pr "%s" indent;
  if extern then pr "extern ";
  if dll_public then pr "GUESTFS_DLL_PUBLIC ";
  if static then pr "static ";
  (match ret with
   | RErr
   | RInt _
   | RBool _ ->
       pr "int";
       if single_line then pr " " else pr "\n%s" indent
   | RInt64 _ ->
       pr "int64_t";
       if single_line then pr " " else pr "\n%s" indent
   | RConstString _ | RConstOptString _ ->
       pr "const char *";
       if not single_line then pr "\n%s" indent
   | RString _ | RBufferOut _ ->
       pr "char *";
       if not single_line then pr "\n%s" indent
   | RStringList _ | RHashtable _ ->
       pr "char **";
       if not single_line then pr "\n%s" indent
   | RStruct (_, typ) ->
       if not in_daemon then pr "struct guestfs_%s *" typ
       else pr "guestfs_int_%s *" typ;
       if not single_line then pr "\n%s" indent
   | RStructList (_, typ) ->
       if not in_daemon then pr "struct guestfs_%s_list *" typ
       else pr "guestfs_int_%s_list *" typ;
       if not single_line then pr "\n%s" indent
  );
  let is_RBufferOut = match ret with RBufferOut _ -> true | _ -> false in
  pr "%s%s%s (" prefix name suffix;
  if handle = None && args = [] && optargs = [] && not is_RBufferOut then
      pr "void"
  else (
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
      | Key n ->
          next ();
          pr "const char *%s" n
      | StringList n | DeviceList n ->
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
          pr "%s %s" t n
    ) args;
    if is_RBufferOut then (next (); pr "size_t *size_r");
    if optargs <> [] then (
      next ();
      match optarg_proto with
      | Dots -> pr "..."
      | VA -> pr "va_list args"
      | Argv -> pr "const struct guestfs_%s_argv *optargs" name
    );
  );
  pr ")";
  if semicolon then pr ";";
  if newline then pr "\n"

(* Generate C call arguments, eg "(handle, foo, bar)" *)
and generate_c_call_args ?handle ?(implicit_size_ptr = "&size")
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
  List.iter (
    fun (shortname, (ret, args, optargs as style), _, flags, _, _, longdesc) ->
      if not (List.mem NotInDocs flags) then (
        let name = "guestfs_" ^ shortname in
        pr "=head2 %s\n\n" name;
        generate_prototype ~extern:false ~indent:" " ~handle:"g" name style;
        pr "\n\n";

        (match deprecation_notice ~prefix:"guestfs_" flags with
         | None -> ()
         | Some txt -> pr "%s\n\n" txt
        );

        let uc_shortname = String.uppercase shortname in
        if optargs <> [] then (
          pr "You may supply a list of optional arguments to this call.\n";
          pr "Use zero or more of the following pairs of parameters,\n";
          pr "and terminate the list with C<-1> on its own.\n";
          pr "See L</CALLS WITH OPTIONAL ARGUMENTS>.\n\n";
          List.iter (
            fun argt ->
              let n = name_of_optargt argt in
              let uc_n = String.uppercase n in
              pr " GUESTFS_%s_%s, " uc_shortname uc_n;
              match argt with
              | OBool n -> pr "int %s,\n" n
              | OInt n -> pr "int %s,\n" n
              | OInt64 n -> pr "int64_t %s,\n" n
              | OString n -> pr "const char *%s,\n" n
          ) optargs;
          pr "\n";
        );

        pr "%s\n\n" longdesc;
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
        if List.mem Progress flags then
          pr "%s\n\n" progress_message;
        if List.mem ProtocolLimitWarning flags then
          pr "%s\n\n" protocol_limit_warning;
        if List.exists (function Key _ -> true | _ -> false) args then
          pr "This function takes a key or passphrase parameter which
could contain sensitive material.  Read the section
L</KEYS AND PASSPHRASES> for more information.\n\n";
        (match lookup_api_version name with
         | Some version -> pr "(Added in %s)\n\n" version
         | None -> ()
        );

        (* Handling of optional argument variants. *)
        if optargs <> [] then (
          pr "=head2 %s_va\n\n" name;
          generate_prototype ~extern:false ~indent:" " ~handle:"g"
            ~prefix:"guestfs_" ~suffix:"_va" ~optarg_proto:VA
            shortname style;
          pr "\n\n";
          pr "This is the \"va_list variant\" of L</%s>.\n\n" name;
          pr "See L</CALLS WITH OPTIONAL ARGUMENTS>.\n\n";
          pr "=head2 %s_argv\n\n" name;
          generate_prototype ~extern:false ~indent:" " ~handle:"g"
            ~prefix:"guestfs_" ~suffix:"_argv" ~optarg_proto:Argv
            shortname style;
          pr "\n\n";
          pr "This is the \"argv variant\" of L</%s>.\n\n" name;
          pr "See L</CALLS WITH OPTIONAL ARGUMENTS>.\n\n";
        );
      )
  ) all_functions_sorted

and generate_structs_pod () =
  (* Structs documentation. *)
  List.iter (
    fun (typ, cols) ->
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
      pr " \n";
      pr " void guestfs_free_%s (struct guestfs_free_%s *);\n" typ typ;
      pr " void guestfs_free_%s_list (struct guestfs_free_%s_list *);\n"
        typ typ;
      pr "\n"
  ) structs

and generate_availability_pod () =
  (* Availability documentation. *)
  pr "=over 4\n";
  pr "\n";
  List.iter (
    fun (group, functions) ->
      pr "=item B<%s>\n" group;
      pr "\n";
      pr "The following functions:\n";
      List.iter (pr "L</guestfs_%s>\n") functions;
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
 * Go and read it now, I'll be right here waiting for you
 * when you come back.
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

#ifdef __GNUC__
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
#endif

/* The handle. */
#ifndef GUESTFS_TYPEDEF_H
#define GUESTFS_TYPEDEF_H 1
typedef struct guestfs_h guestfs_h;
#endif

/* Connection management. */
extern GUESTFS_DLL_PUBLIC guestfs_h *guestfs_create (void);
extern GUESTFS_DLL_PUBLIC void guestfs_close (guestfs_h *g);

/* Error handling. */
extern GUESTFS_DLL_PUBLIC const char *guestfs_last_error (guestfs_h *g);
#define LIBGUESTFS_HAVE_LAST_ERRNO 1
extern GUESTFS_DLL_PUBLIC int guestfs_last_errno (guestfs_h *g);

#ifndef GUESTFS_TYPEDEF_ERROR_HANDLER_CB
#define GUESTFS_TYPEDEF_ERROR_HANDLER_CB 1
typedef void (*guestfs_error_handler_cb) (guestfs_h *g, void *opaque, const char *msg);
#endif

#ifndef GUESTFS_TYPEDEF_ABORT_CB
#define GUESTFS_TYPEDEF_ABORT_CB 1
typedef void (*guestfs_abort_cb) (void) __attribute__((__noreturn__));
#endif

extern GUESTFS_DLL_PUBLIC void guestfs_set_error_handler (guestfs_h *g, guestfs_error_handler_cb cb, void *opaque);
extern GUESTFS_DLL_PUBLIC guestfs_error_handler_cb guestfs_get_error_handler (guestfs_h *g, void **opaque_rtn);

extern GUESTFS_DLL_PUBLIC void guestfs_set_out_of_memory_handler (guestfs_h *g, guestfs_abort_cb);
extern GUESTFS_DLL_PUBLIC guestfs_abort_cb guestfs_get_out_of_memory_handler (guestfs_h *g);

/* Events. */
";

  List.iter (
    fun (name, bitmask) ->
      pr "#define GUESTFS_EVENT_%-16s 0x%04x\n"
        (String.uppercase name) bitmask
  ) events;
  pr "#define GUESTFS_EVENT_%-16s UINT64_MAX\n" "ALL";
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

#define LIBGUESTFS_HAVE_SET_EVENT_CALLBACK 1
extern GUESTFS_DLL_PUBLIC int guestfs_set_event_callback (guestfs_h *g, guestfs_event_callback cb, uint64_t event_bitmask, int flags, void *opaque);
#define LIBGUESTFS_HAVE_DELETE_EVENT_CALLBACK 1
extern GUESTFS_DLL_PUBLIC void guestfs_delete_event_callback (guestfs_h *g, int event_handle);

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
#define LIBGUESTFS_HAVE_SET_CLOSE_CALLBACK 1
extern GUESTFS_DLL_PUBLIC void guestfs_set_close_callback (guestfs_h *g, guestfs_close_cb cb, void *opaque)
  GUESTFS_DEPRECATED_BY(\"set_event_callback\");
#define LIBGUESTFS_HAVE_SET_PROGRESS_CALLBACK 1
extern GUESTFS_DLL_PUBLIC void guestfs_set_progress_callback (guestfs_h *g, guestfs_progress_cb cb, void *opaque)
  GUESTFS_DEPRECATED_BY(\"set_event_callback\");

/* User cancellation. */
#define LIBGUESTFS_HAVE_USER_CANCEL 1
extern GUESTFS_DLL_PUBLIC void guestfs_user_cancel (guestfs_h *g);

/* Private data area. */
#define LIBGUESTFS_HAVE_SET_PRIVATE 1
extern GUESTFS_DLL_PUBLIC void guestfs_set_private (guestfs_h *g, const char *key, void *data);
#define LIBGUESTFS_HAVE_GET_PRIVATE 1
extern GUESTFS_DLL_PUBLIC void *guestfs_get_private (guestfs_h *g, const char *key);
#define LIBGUESTFS_HAVE_FIRST_PRIVATE 1
extern GUESTFS_DLL_PUBLIC void *guestfs_first_private (guestfs_h *g, const char **key_rtn);
#define LIBGUESTFS_HAVE_NEXT_PRIVATE 1
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
  List.iter (
    fun (typ, cols) ->
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
      pr "extern GUESTFS_DLL_PUBLIC void guestfs_free_%s (struct guestfs_%s *);\n" typ typ;
      pr "extern GUESTFS_DLL_PUBLIC void guestfs_free_%s_list (struct guestfs_%s_list *);\n" typ typ;
      pr "\n"
  ) structs;

  pr "\
/* Actions. */
";

  List.iter (
    fun (shortname, (ret, args, optargs as style), _, flags, _, _, _) ->
      let deprecated =
        try
          Some (find_map (function DeprecatedBy fn -> Some fn | _ -> None)
                  flags)
        with Not_found -> None in
      let test0 =
        String.length shortname >= 5 && String.sub shortname 0 5 = "test0" in
      let debug =
        String.length shortname >= 5 && String.sub shortname 0 5 = "debug" in
      if deprecated = None && not test0 && not debug then
        pr "#define LIBGUESTFS_HAVE_%s 1\n" (String.uppercase shortname);

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
      (match deprecated with
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
              | OString n -> "const char *" in
            let uc_shortname = String.uppercase shortname in
            let n = name_of_optargt argt in
            let uc_n = String.uppercase n in
            pr "\n";
            pr "# define GUESTFS_%s_%s_BITMASK (UINT64_C(1)<<%d)\n" uc_shortname uc_n i;
            pr "  /* The field below is only valid in this struct if the\n";
            pr "   * GUESTFS_%s_%s_BITMASK bit is set\n" uc_shortname uc_n;
            pr "   * in the bitmask above.  If not, the field is ignored.\n";
            pr "   */\n";
            pr "  %s%s;\n" c_type n
        ) optargs;
        pr "};\n";
        pr "\n";

        generate_prototype ~single_line:true ~newline:true ~handle:"g"
          ~prefix:"guestfs_" ~suffix:"_argv" ~optarg_proto:Argv
          ~dll_public:true
          shortname style;
      );

      pr "\n";
  ) all_functions_sorted;

  pr "\

/* Private functions.
 *
 * These are NOT part of the public, stable API, and can change at any
 * time!  We export them because they are used by some of the language
 * bindings.
 */
extern GUESTFS_DLL_PUBLIC void *guestfs_safe_malloc (guestfs_h *g, size_t nbytes);
extern GUESTFS_DLL_PUBLIC void *guestfs_safe_calloc (guestfs_h *g, size_t n, size_t s);
extern GUESTFS_DLL_PUBLIC char *guestfs_safe_strdup (guestfs_h *g, const char *str);
extern GUESTFS_DLL_PUBLIC void *guestfs_safe_memdup (guestfs_h *g, void *ptr, size_t size);
extern GUESTFS_DLL_PUBLIC const char *guestfs_tmpdir (void);
#ifdef GUESTFS_PRIVATE_FOR_EACH_DISK
extern GUESTFS_DLL_PUBLIC int guestfs___for_each_disk (guestfs_h *g, virDomainPtr dom, int (*)(guestfs_h *g, const char *filename, const char *format, int readonly, void *data), void *data);
#endif
/* End of private functions. */

#ifdef __cplusplus
}
#endif

#endif /* GUESTFS_H_ */
"

(* Generate the guestfs-internal-actions.h file. *)
and generate_internal_actions_h () =
  generate_header CStyle LGPLv2plus;
  List.iter (
    fun (shortname, style, _, _, _, _, _) ->
      generate_prototype ~single_line:true ~newline:true ~handle:"g"
        ~prefix:"guestfs__" ~optarg_proto:Argv
        shortname style
  ) non_daemon_functions

(* Generate the client-side dispatch stubs. *)
and generate_client_actions () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <inttypes.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <assert.h>

#include \"guestfs.h\"
#include \"guestfs-internal.h\"
#include \"guestfs-internal-actions.h\"
#include \"guestfs_protocol.h\"
#include \"errnostring.h\"

/* Check the return message from a call for validity. */
static int
check_reply_header (guestfs_h *g,
                    const struct guestfs_message_header *hdr,
                    unsigned int proc_nr, unsigned int serial)
{
  if (hdr->prog != GUESTFS_PROGRAM) {
    error (g, \"wrong program (%%d/%%d)\", hdr->prog, GUESTFS_PROGRAM);
    return -1;
  }
  if (hdr->vers != GUESTFS_PROTOCOL_VERSION) {
    error (g, \"wrong protocol version (%%d/%%d)\",
           hdr->vers, GUESTFS_PROTOCOL_VERSION);
    return -1;
  }
  if (hdr->direction != GUESTFS_DIRECTION_REPLY) {
    error (g, \"unexpected message direction (%%d/%%d)\",
           hdr->direction, GUESTFS_DIRECTION_REPLY);
    return -1;
  }
  if (hdr->proc != proc_nr) {
    error (g, \"unexpected procedure number (%%d/%%d)\", hdr->proc, proc_nr);
    return -1;
  }
  if (hdr->serial != serial) {
    error (g, \"unexpected serial (%%d/%%d)\", hdr->serial, serial);
    return -1;
  }

  return 0;
}

/* Check the appliance is up when running a daemon_function. */
static int
check_appliance_up (guestfs_h *g, const char *caller)
{
  if (guestfs__is_config (g) || guestfs__is_launching (g)) {
    error (g, \"%%s: call launch before using this function\\n(in guestfish, don't forget to use the 'run' command)\",
           caller);
    return -1;
  }
  return 0;
}

/* Convenience wrapper for tracing. */
static FILE *
trace_open (guestfs_h *g)
{
  assert (g->trace_fp == NULL);
  g->trace_buf = NULL;
  g->trace_len = 0;
  g->trace_fp = open_memstream (&g->trace_buf, &g->trace_len);
  if (g->trace_fp)
    return g->trace_fp;
  else
    return stderr;
}

static void
trace_send_line (guestfs_h *g)
{
  char *buf;
  size_t len;

  if (g->trace_fp) {
    fclose (g->trace_fp);
    g->trace_fp = NULL;

    /* The callback might invoke other libguestfs calls, so keep
     * a copy of the pointer to the buffer and length.
     */
    buf = g->trace_buf;
    len = g->trace_len;
    g->trace_buf = NULL;
    guestfs___call_callbacks_message (g, GUESTFS_EVENT_TRACE, buf, len);

    free (buf);
  }
}

";

  (* Generate code for enter events. *)
  let enter_event shortname =
    pr "  guestfs___call_callbacks_message (g, GUESTFS_EVENT_ENTER,\n";
    pr "                                    \"%s\", %d);\n"
      shortname (String.length shortname)
  in

  (* Generate code to check String-like parameters are not passed in
   * as NULL (returning an error if they are).
   *)
  let check_null_strings shortname (ret, args, optargs) =
    let pr_newline = ref false in
    List.iter (
      function
      (* parameters which should not be NULL *)
      | String n
      | Device n
      | Pathname n
      | Dev_or_Path n
      | FileIn n
      | FileOut n
      | BufferIn n
      | StringList n
      | DeviceList n
      | Key n
      | Pointer (_, n) ->
          pr "  if (%s == NULL) {\n" n;
          pr "    error (g, \"%%s: %%s: parameter cannot be NULL\",\n";
          pr "           \"%s\", \"%s\");\n" shortname n;
          let errcode =
            match errcode_of_ret ret with
            | `CannotReturnError ->
                if shortname = "test0rconstoptstring" then (* XXX hack *)
                  `ErrorIsNULL
                else
                  failwithf
                    "%s: RConstOptString function has invalid parameter '%s'"
                    shortname n
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
            (String.uppercase shortname) (String.uppercase n);
          pr "      optargs->%s == NULL) {\n" n;
          pr "    error (g, \"%%s: %%s: optional parameter cannot be NULL\",\n";
          pr "           \"%s\", \"%s\");\n" shortname n;
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
  let reject_unknown_optargs shortname = function
    | _, _, [] -> ()
    | ret, _, optargs ->
        let len = List.length optargs in
        let mask = Int64.lognot (Int64.pred (Int64.shift_left 1L len)) in
        pr "  if (optargs->bitmask & UINT64_C(0x%Lx)) {\n" mask;
        pr "    error (g, \"%%s: unknown option in guestfs_%%s_argv->bitmask (this can happen if a program is compiled against a newer version of libguestfs, then dynamically linked to an older version)\",\n";
        pr "           \"%s\", \"%s\");\n" shortname shortname;
        let errcode =
          match errcode_of_ret ret with
          | `CannotReturnError -> assert false
          | (`ErrorIsMinusOne |`ErrorIsNULL) as e -> e in
        pr "    return %s;\n" (string_of_errcode errcode);
        pr "  }\n";
        pr "\n";
  in

  (* Generate code to generate guestfish call traces. *)
  let trace_call shortname (ret, args, optargs) =
    pr "  if (trace_flag) {\n";

    let needs_i =
      List.exists (function
                   | StringList _ | DeviceList _ -> true
                   | _ -> false) args in
    if needs_i then (
      pr "    size_t i;\n";
      pr "\n"
    );

    pr "    trace_fp = trace_open (g);\n";

    pr "    fprintf (trace_fp, \"%%s\", \"%s\");\n" shortname;

    (* Required arguments. *)
    List.iter (
      function
      | String n			(* strings *)
      | Device n
      | Pathname n
      | Dev_or_Path n
      | FileIn n
      | FileOut n ->
          (* guestfish doesn't support string escaping, so neither do we *)
          pr "    fprintf (trace_fp, \" \\\"%%s\\\"\", %s);\n" n
      | Key n ->
          (* don't print keys *)
          pr "    fprintf (trace_fp, \" \\\"***\\\"\");\n"
      | OptString n ->			(* string option *)
          pr "    if (%s) fprintf (trace_fp, \" \\\"%%s\\\"\", %s);\n" n n;
          pr "    else fprintf (trace_fp, \" null\");\n"
      | StringList n
      | DeviceList n ->			(* string list *)
          pr "    fputc (' ', trace_fp);\n";
          pr "    fputc ('\"', trace_fp);\n";
          pr "    for (i = 0; %s[i]; ++i) {\n" n;
          pr "      if (i > 0) fputc (' ', trace_fp);\n";
          pr "      fputs (%s[i], trace_fp);\n" n;
          pr "    }\n";
          pr "    fputc ('\"', trace_fp);\n";
      | Bool n ->			(* boolean *)
          pr "    fputs (%s ? \" true\" : \" false\", trace_fp);\n" n
      | Int n ->			(* int *)
          pr "    fprintf (trace_fp, \" %%d\", %s);\n" n
      | Int64 n ->
          pr "    fprintf (trace_fp, \" %%\" PRIi64, %s);\n" n
      | BufferIn n ->                   (* RHBZ#646822 *)
          pr "    fputc (' ', trace_fp);\n";
          pr "    guestfs___print_BufferIn (trace_fp, %s, %s_size);\n" n n
      | Pointer (t, n) ->
          pr "    fprintf (trace_fp, \" (%s)%%p\", %s);\n" t n
    ) args;

    (* Optional arguments. *)
    List.iter (
      fun argt ->
        let n = name_of_optargt argt in
        let uc_shortname = String.uppercase shortname in
        let uc_n = String.uppercase n in
        pr "    if (optargs->bitmask & GUESTFS_%s_%s_BITMASK)\n"
          uc_shortname uc_n;
        (match argt with
         | OString n ->
             pr "      fprintf (trace_fp, \" \\\"%%s:%%s\\\"\", \"%s\", optargs->%s);\n" n n
         | OBool n ->
             pr "      fprintf (trace_fp, \" \\\"%%s:%%s\\\"\", \"%s\", optargs->%s ? \"true\" : \"false\");\n" n n
         | OInt n ->
             pr "      fprintf (trace_fp, \" \\\"%%s:%%d\\\"\", \"%s\", optargs->%s);\n" n n
         | OInt64 n ->
             pr "      fprintf (trace_fp, \" \\\"%%s:%%\" PRIi64 \"\\\"\", \"%s\", optargs->%s);\n" n n
        );
    ) optargs;

    pr "    trace_send_line (g);\n";
    pr "  }\n";
    pr "\n";
  in

  let trace_return ?(indent = 2) shortname (ret, _, _) rv =
    let indent = spaces indent in

    pr "%sif (trace_flag) {\n" indent;

    let needs_i =
      match ret with
      | RStringList _ | RHashtable _ -> true
      | _ -> false in
    if needs_i then (
      pr "%s  size_t i;\n" indent;
      pr "\n"
    );

    pr "%s  trace_fp = trace_open (g);\n" indent;

    pr "%s  fprintf (trace_fp, \"%%s = \", \"%s\");\n" indent shortname;

    (match ret with
     | RErr | RInt _ | RBool _ ->
         pr "%s  fprintf (trace_fp, \"%%d\", %s);\n" indent rv
     | RInt64 _ ->
         pr "%s  fprintf (trace_fp, \"%%\" PRIi64, %s);\n" indent rv
     | RConstString _ | RString _ ->
         pr "%s  fprintf (trace_fp, \"\\\"%%s\\\"\", %s);\n" indent rv
     | RConstOptString _ ->
         pr "%s  fprintf (trace_fp, \"\\\"%%s\\\"\", %s != NULL ? %s : \"NULL\");\n"
           indent rv rv
     | RBufferOut _ ->
         pr "%s  guestfs___print_BufferOut (trace_fp, %s, *size_r);\n" indent rv
     | RStringList _ | RHashtable _ ->
         pr "%s  fputs (\"[\", trace_fp);\n" indent;
         pr "%s  for (i = 0; %s[i]; ++i) {\n" indent rv;
         pr "%s    if (i > 0) fputs (\", \", trace_fp);\n" indent;
         pr "%s    fputs (\"\\\"\", trace_fp);\n" indent;
         pr "%s    fputs (%s[i], trace_fp);\n" indent rv;
         pr "%s    fputs (\"\\\"\", trace_fp);\n" indent;
         pr "%s  }\n" indent;
         pr "%s  fputs (\"]\", trace_fp);\n" indent;
     | RStruct (_, typ) ->
         (* XXX There is code generated for guestfish for printing
          * these structures.  We need to make it generally available
          * for all callers
          *)
         pr "%s  fprintf (trace_fp, \"<struct guestfs_%s *>\");\n"
           indent typ (* XXX *)
     | RStructList (_, typ) ->
         pr "%s  fprintf (trace_fp, \"<struct guestfs_%s_list *>\");\n"
           indent typ (* XXX *)
    );
    pr "%s  trace_send_line (g);\n" indent;
    pr "%s}\n" indent;
    pr "\n";
  in

  let trace_return_error ?(indent = 2) shortname (ret, _, _) errcode =
    let indent = spaces indent in

    pr "%sif (trace_flag)\n" indent;

    pr "%s  guestfs___trace (g, \"%%s = %%s (error)\",\n" indent;
    pr "%s                   \"%s\", \"%s\");\n"
      indent shortname (string_of_errcode errcode)
  in

  let handle_null_optargs optargs shortname =
    if optargs <> [] then (
      pr "  struct guestfs_%s_argv optargs_null;\n" shortname;
      pr "  if (!optargs) {\n";
      pr "    optargs_null.bitmask = 0;\n";
      pr "    optargs = &optargs_null;\n";
      pr "  }\n\n";
    )
  in

  (* For non-daemon functions, generate a wrapper around each function. *)
  List.iter (
    fun (shortname, (ret, _, optargs as style), _, flags, _, _, _) ->
      if optargs = [] then
        generate_prototype ~extern:false ~semicolon:false ~newline:true
          ~handle:"g" ~prefix:"guestfs_"
          shortname style
      else
        generate_prototype ~extern:false ~semicolon:false ~newline:true
          ~handle:"g" ~prefix:"guestfs_" ~suffix:"_argv" ~optarg_proto:Argv
          shortname style;
      pr "{\n";

      handle_null_optargs optargs shortname;

      pr "  int trace_flag = g->trace;\n";
      pr "  FILE *trace_fp;\n";
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
      if List.mem ConfigOnly flags then (
        pr "  if (g->state != CONFIG) {\n";
        pr "    error (g, \"%%s: this function can only be called in the config state\",\n";
        pr "              \"%s\");\n" shortname;
        pr "    return -1;\n";
        pr "  }\n";
      );
      enter_event shortname;
      check_null_strings shortname style;
      reject_unknown_optargs shortname style;
      trace_call shortname style;
      pr "  r = guestfs__%s " shortname;
      generate_c_call_args ~handle:"g" ~implicit_size_ptr:"size_r" style;
      pr ";\n";
      pr "\n";
      (match errcode_of_ret ret with
       | (`ErrorIsMinusOne | `ErrorIsNULL) as errcode ->
           pr "  if (r != %s) {\n" (string_of_errcode errcode);
           trace_return ~indent:4 shortname style "r";
           pr "  } else {\n";
           trace_return_error ~indent:4 shortname style errcode;
           pr "  }\n";
       | `CannotReturnError ->
           trace_return shortname style "r";
      );
      pr "\n";
      pr "  return r;\n";
      pr "}\n";
      pr "\n"
  ) non_daemon_functions;

  (* Client-side stubs for each function. *)
  List.iter (
    fun (shortname, (ret, args, optargs as style), _, _, _, _, _) ->
      let name = "guestfs_" ^ shortname in
      let errcode =
        match errcode_of_ret ret with
        | `CannotReturnError -> assert false
        | (`ErrorIsMinusOne | `ErrorIsNULL) as e -> e in

      (* Generate the action stub. *)
      if optargs = [] then
        generate_prototype ~extern:false ~semicolon:false ~newline:true
          ~handle:"g" ~prefix:"guestfs_" shortname style
      else
        generate_prototype ~extern:false ~semicolon:false ~newline:true
          ~handle:"g" ~prefix:"guestfs_" ~suffix:"_argv"
          ~optarg_proto:Argv shortname style;

      pr "{\n";

      handle_null_optargs optargs shortname;

      (match args with
       | [] -> ()
       | _ -> pr "  struct %s_args args;\n" name
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
            pr "  struct %s_ret ret;\n" name;
            true in

      pr "  int serial;\n";
      pr "  int r;\n";
      pr "  int trace_flag = g->trace;\n";
      pr "  FILE *trace_fp;\n";
      (match ret with
       | RErr | RInt _ | RBool _ ->
           pr "  int ret_v;\n"
       | RInt64 _ ->
           pr "  int64_t ret_v;\n"
       | RConstString _ | RConstOptString _ ->
           pr "  const char *ret_v;\n"
       | RString _ | RBufferOut _ ->
           pr "  char *ret_v;\n"
       | RStringList _ | RHashtable _ ->
           pr "  char **ret_v;\n"
       | RStruct (_, typ) ->
           pr "  struct guestfs_%s *ret_v;\n" typ
       | RStructList (_, typ) ->
           pr "  struct guestfs_%s_list *ret_v;\n" typ
      );

      let has_filein =
        List.exists (function FileIn _ -> true | _ -> false) args in
      if has_filein then (
        pr "  uint64_t progress_hint = 0;\n";
        pr "  struct stat progress_stat;\n";
      ) else
        pr "  const uint64_t progress_hint = 0;\n";

      pr "\n";
      enter_event shortname;
      check_null_strings shortname style;
      reject_unknown_optargs shortname style;
      trace_call shortname style;

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
      pr "  if (check_appliance_up (g, \"%s\") == -1) {\n" shortname;
      trace_return_error ~indent:4 shortname style errcode;
      pr "    return %s;\n" (string_of_errcode errcode);
      pr "  }\n";
      pr "\n";

      (* Send the main header and arguments. *)
      if args = [] && optargs = [] then (
        pr "  serial = guestfs___send (g, GUESTFS_PROC_%s, progress_hint, 0,\n"
          (String.uppercase shortname);
        pr "                           NULL, NULL);\n"
      ) else (
        List.iter (
          function
          | Pathname n | Device n | Dev_or_Path n | String n | Key n ->
              pr "  args.%s = (char *) %s;\n" n n
          | OptString n ->
              pr "  args.%s = %s ? (char **) &%s : NULL;\n" n n n
          | StringList n | DeviceList n ->
              pr "  args.%s.%s_val = (char **) %s;\n" n n n;
              pr "  for (args.%s.%s_len = 0; %s[args.%s.%s_len]; args.%s.%s_len++) ;\n" n n n n n n n;
          | Bool n ->
              pr "  args.%s = %s;\n" n n
          | Int n ->
              pr "  args.%s = %s;\n" n n
          | Int64 n ->
              pr "  args.%s = %s;\n" n n
          | FileIn _ | FileOut _ -> ()
          | BufferIn n ->
              pr "  /* Just catch grossly large sizes. XDR encoding will make this precise. */\n";
              pr "  if (%s_size >= GUESTFS_MESSAGE_MAX) {\n" n;
              trace_return_error ~indent:4 shortname style errcode;
              pr "    error (g, \"%%s: size of input buffer too large\", \"%s\");\n"
                shortname;
              pr "    return %s;\n" (string_of_errcode errcode);
              pr "  }\n";
              pr "  args.%s.%s_val = (char *) %s;\n" n n n;
              pr "  args.%s.%s_len = %s_size;\n" n n n
          | Pointer _ -> assert false
        ) args;

        List.iter (
          fun argt ->
            let n = name_of_optargt argt in
            let uc_shortname = String.uppercase shortname in
            let uc_n = String.uppercase n in
            pr "  if (optargs->bitmask & GUESTFS_%s_%s_BITMASK)\n"
              uc_shortname uc_n;
            (match argt with
             | OBool n
             | OInt n
             | OInt64 n ->
                 pr "    args.%s = optargs->%s;\n" n n;
                 pr "  else\n";
                 pr "    args.%s = 0;\n" n
             | OString n ->
                 pr "    args.%s = (char *) optargs->%s;\n" n n;
                 pr "  else\n";
                 pr "    args.%s = (char *) \"\";\n" n
            )
        ) optargs;

        pr "  serial = guestfs___send (g, GUESTFS_PROC_%s,\n"
          (String.uppercase shortname);
        pr "                           progress_hint, %s,\n"
          (if optargs <> [] then "optargs->bitmask" else "0");
        pr "                           (xdrproc_t) xdr_%s_args, (char *) &args);\n"
          name;
      );
      pr "  if (serial == -1) {\n";
      trace_return_error ~indent:4 shortname style errcode;
      pr "    return %s;\n" (string_of_errcode errcode);
      pr "  }\n";
      pr "\n";

      (* Send any additional files (FileIn) requested. *)
      let need_read_reply_label = ref false in
      List.iter (
        function
        | FileIn n ->
            pr "  r = guestfs___send_file (g, %s);\n" n;
            pr "  if (r == -1) {\n";
            trace_return_error ~indent:4 shortname style errcode;
            pr "    /* daemon will send an error reply which we discard */\n";
            pr "    guestfs___recv_discard (g, \"%s\");\n" shortname;
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
      pr "  r = guestfs___recv (g, \"%s\", &hdr, &err,\n        " shortname;
      if not has_ret then
        pr "NULL, NULL"
      else
        pr "(xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret" shortname;
      pr ");\n";

      pr "  if (r == -1) {\n";
      trace_return_error ~indent:4 shortname style errcode;
      pr "    return %s;\n" (string_of_errcode errcode);
      pr "  }\n";
      pr "\n";

      pr "  if (check_reply_header (g, &hdr, GUESTFS_PROC_%s, serial) == -1) {\n"
        (String.uppercase shortname);
      trace_return_error ~indent:4 shortname style errcode;
      pr "    return %s;\n" (string_of_errcode errcode);
      pr "  }\n";
      pr "\n";

      pr "  if (hdr.status == GUESTFS_STATUS_ERROR) {\n";
      trace_return_error ~indent:4 shortname style errcode;
      pr "    int errnum = 0;\n";
      pr "    if (err.errno_string[0] != '\\0')\n";
      pr "      errnum = guestfs___string_to_errno (err.errno_string);\n";
      pr "    if (errnum <= 0)\n";
      pr "      error (g, \"%%s: %%s\", \"%s\", err.error_message);\n"
        shortname;
      pr "    else\n";
      pr "      guestfs_error_errno (g, errnum, \"%%s: %%s\", \"%s\",\n"
        shortname;
      pr "                           err.error_message);\n";
      pr "    free (err.error_message);\n";
      pr "    free (err.errno_string);\n";
      pr "    return %s;\n" (string_of_errcode errcode);
      pr "  }\n";
      pr "\n";

      (* Expecting to receive further files (FileOut)? *)
      List.iter (
        function
        | FileOut n ->
            pr "  if (guestfs___recv_file (g, %s) == -1) {\n" n;
            trace_return_error ~indent:4 shortname style errcode;
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
      trace_return shortname style "ret_v";
      pr "  return ret_v;\n";
      pr "}\n\n"
  ) daemon_functions;

  (* Functions to free structures. *)
  pr "/* Structure-freeing functions.  These rely on the fact that the\n";
  pr " * structure format is identical to the XDR format.  See note in\n";
  pr " * generator.ml.\n";
  pr " */\n";
  pr "\n";

  List.iter (
    fun (typ, _) ->
      pr "void\n";
      pr "guestfs_free_%s (struct guestfs_%s *x)\n" typ typ;
      pr "{\n";
      pr "  xdr_free ((xdrproc_t) xdr_guestfs_int_%s, (char *) x);\n" typ;
      pr "  free (x);\n";
      pr "}\n";
      pr "\n";

      pr "void\n";
      pr "guestfs_free_%s_list (struct guestfs_%s_list *x)\n" typ typ;
      pr "{\n";
      pr "  xdr_free ((xdrproc_t) xdr_guestfs_int_%s_list, (char *) x);\n" typ;
      pr "  free (x);\n";
      pr "}\n";
      pr "\n";

  ) structs;

  (* Functions which have optional arguments have two generated variants. *)
  List.iter (
    function
    | shortname, (ret, args, (_::_ as optargs) as style), _, _, _, _, _ ->
        let uc_shortname = String.uppercase shortname in

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
          ~handle:"g" ~prefix:"guestfs_" shortname style;
        pr "{\n";
        pr "  va_list optargs;\n";
        pr "\n";
        pr "  va_start (optargs, %s);\n" last_arg;
        pr "  %sr = guestfs_%s_va " rtype shortname;
        generate_c_call_args ~handle:"g" ~implicit_size_ptr:"size_r" style;
        pr ";\n";
        pr "  va_end (optargs);\n";
        pr "\n";
        pr "  return r;\n";
        pr "}\n\n";

        generate_prototype ~extern:false ~semicolon:false ~newline:true
          ~handle:"g" ~prefix:"guestfs_" ~suffix:"_va" ~optarg_proto:VA
          shortname style;
        pr "{\n";
        pr "  struct guestfs_%s_argv optargs_s;\n" shortname;
        pr "  struct guestfs_%s_argv *optargs = &optargs_s;\n" shortname;
        pr "  int i;\n";
        pr "\n";
        pr "  optargs_s.bitmask = 0;\n";
        pr "\n";
        pr "  while ((i = va_arg (args, int)) >= 0) {\n";
        pr "    switch (i) {\n";

        List.iter (
          fun argt ->
            let n = name_of_optargt argt in
            let uc_n = String.uppercase n in
            pr "    case GUESTFS_%s_%s:\n" uc_shortname uc_n;
            pr "      optargs_s.%s = va_arg (args, " n;
            (match argt with
             | OBool _ | OInt _ -> pr "int"
             | OInt64 _ -> pr "int64_t"
             | OString _ -> pr "const char *"
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
        pr "             \"%s\", i);\n" shortname;
        pr "      return %s;\n" (string_of_errcode errcode);
        pr "    }\n";
        pr "\n";
        pr "    uint64_t i_mask = UINT64_C(1) << i;\n";
        pr "    if (optargs_s.bitmask & i_mask) {\n";
        pr "      error (g, \"%%s: same optional argument specified more than once\",\n";
        pr "             \"%s\");\n" shortname;
        pr "      return %s;\n" (string_of_errcode errcode);
        pr "    }\n";
        pr "    optargs_s.bitmask |= i_mask;\n";
        pr "  }\n";
        pr "\n";
        pr "  return guestfs_%s_argv " shortname;
        generate_c_call_args ~handle:"g" ~implicit_size_ptr:"size_r" style;
        pr ";\n";
        pr "}\n\n"
    | _ -> ()
  ) all_functions_sorted

(* Generate the linker script which controls the visibility of
 * symbols in the public ABI and ensures no other symbols get
 * exported accidentally.
 *)
and generate_linker_script () =
  generate_header HashStyle GPLv2plus;

  let globals = [
    "guestfs_create";
    "guestfs_close";
    "guestfs_delete_event_callback";
    "guestfs_first_private";
    "guestfs_get_error_handler";
    "guestfs_get_out_of_memory_handler";
    "guestfs_get_private";
    "guestfs_last_errno";
    "guestfs_last_error";
    "guestfs_next_private";
    "guestfs_set_close_callback";
    "guestfs_set_error_handler";
    "guestfs_set_event_callback";
    "guestfs_set_launch_done_callback";
    "guestfs_set_log_message_callback";
    "guestfs_set_out_of_memory_handler";
    "guestfs_set_private";
    "guestfs_set_progress_callback";
    "guestfs_set_subprocess_quit_callback";
    "guestfs_user_cancel";

    (* Unofficial parts of the API: the bindings code use these
     * functions, so it is useful to export them.
     *)
    "guestfs_safe_calloc";
    "guestfs_safe_malloc";
    "guestfs_safe_strdup";
    "guestfs_safe_memdup";
    "guestfs_tmpdir";
    "guestfs___for_each_disk";
  ] in
  let functions =
    List.flatten (
      List.map (
        function
        | name, (_, _, []), _, _, _, _, _ -> ["guestfs_" ^ name]
        | name, (_, _, _), _, _, _, _, _ ->
            ["guestfs_" ^ name;
             "guestfs_" ^ name ^ "_va";
             "guestfs_" ^ name ^ "_argv"]
      ) all_functions
    ) in
  let structs =
    List.concat (
      List.map (fun (typ, _) ->
                  ["guestfs_free_" ^ typ; "guestfs_free_" ^ typ ^ "_list"])
        structs
    ) in
  let globals = List.sort compare (globals @ functions @ structs) in

  pr "{\n";
  pr "    global:\n";
  List.iter (pr "        %s;\n") globals;
  pr "\n";

  pr "    local:\n";
  pr "        *;\n";
  pr "};\n"

and generate_max_proc_nr () =
  pr "%d\n" max_proc_nr
