(* libguestfs
 * Copyright (C) 2009-2023 Red Hat Inc.
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

open Std_utils
open Types
open Utils
open Pr
open Docstrings
open Optgroups
open Actions
open Structs
open Events
open C

let generate_header = generate_header ~inputs:["generator/java.ml"]

let drop_empty_trailing_lines l =
  let rec loop = function
    | "" :: tl -> loop tl
    | x -> x
  in
  List.rev (loop (List.rev l))

(* Generate Java bindings GuestFS.java file. *)
let rec generate_java_java () =
  generate_header CStyle LGPLv2plus;

  pr "\
package com.redhat.et.libguestfs;

import java.util.HashMap;
import java.util.Map;

/**
 * <p>
 * Libguestfs handle.
 * </p><p>
 * The <code>GuestFS</code> object corresponds to a libguestfs handle.
 * </p><p>
 * Note that the main documentation for the libguestfs API is in
 * the following man pages:
 * </p>
 * <ol>
 * <li> <a href=\"http://libguestfs.org/guestfs-java.3.html\"><code>guestfs-java(3)</code></a> and </li>
 * <li> <a href=\"http://libguestfs.org/guestfs.3.html\"><code>guestfs(3)</code></a>. </li>
 * </ol>
 * <p>
 * This javadoc is <b>not</b> a good introduction to using libguestfs.
 * </p>
 *
 * @author rjones
 */
public class GuestFS {
  // Load the native code.
  static {
    System.loadLibrary (\"guestfs_jni\");
  }

  /**
   * The native guestfs_h pointer.
   */
  long g;

  /* guestfs_create_flags values defined in <guestfs.h> */
  private static int CREATE_NO_ENVIRONMENT   = 1;
  private static int CREATE_NO_CLOSE_ON_EXIT = 2;

  /**
   * Create a libguestfs handle, setting flags.
   *
   * @throws LibGuestFSException If there is a libguestfs error.
   */
  public GuestFS (Map<String, Object> optargs) throws LibGuestFSException
  {
    int flags = 0;

    /* Unpack optional args. */
    Object _optobj;
    _optobj = null;
    if (optargs != null)
      _optobj = optargs.get (\"environment\");
    if (_optobj != null && !((Boolean) _optobj).booleanValue())
      flags |= CREATE_NO_ENVIRONMENT;
    if (optargs != null)
      _optobj = optargs.get (\"close_on_exit\");
    if (_optobj != null && !((Boolean) _optobj).booleanValue())
      flags |= CREATE_NO_CLOSE_ON_EXIT;

    g = _create (flags);
  }

  /**
   * Create a libguestfs handle.
   *
   * @throws LibGuestFSException If there is a libguestfs error.
   */
  public GuestFS () throws LibGuestFSException
  {
    g = _create (0);
  }

  private native long _create (int flags) throws LibGuestFSException;

  /**
   * <p>
   * Close a libguestfs handle.
   * </p><p>
   * You can also leave handles to be collected by the garbage
   * collector, but this method ensures that the resources used
   * by the handle are freed up immediately.  If you call any
   * other methods after closing the handle, you will get an
   * exception.
   * </p>
   *
   * @throws LibGuestFSException If there is a libguestfs error.
   */
  public void close () throws LibGuestFSException
  {
    if (g != 0)
      _close (g);
    g = 0;
  }
  private native void _close (long g) throws LibGuestFSException;

  public void finalize () throws LibGuestFSException
  {
    close ();
  }

";

  (* Events. *)
  pr "  // Event bitmasks.\n\n";
  List.iter (
    fun (name, bitmask) ->
      pr "  /**\n";
      pr "   * Event '%s'.\n" name;
      pr "   *\n";
      pr "   * @see #set_event_callback\n";
      pr "   */\n";
      pr "  public static final long EVENT_%s = 0x%x;\n"
         (String.uppercase_ascii name) bitmask;
      pr "\n";
  ) events;

  pr "  /** Bitmask of all events. */\n";
  pr "  public static final long EVENT_ALL = 0x%x;\n" all_events_bitmask;
  pr "\n";

  pr "\
  /**
   * Utility function to turn an event number or bitmask into a string.
   *
   * @param events the event number to convert
   * @return text representation of event
   */
  public static String eventToString (long events)
  {
    return _event_to_string (events);
  }

  private static native String _event_to_string (long events);

  /**
   * <p>
   * Set an event handler.
   * </p><p>
   * Set an event handler (<code>callback</code>) which is called when any
   * event from the set (<code>events</code>) is raised by the API.
   * <code>events</code> is one or more <code>EVENT_*</code> constants,
   * bitwise ORed together.
   * </p><p>
   * When an event happens, the callback object’s <code>event</code> method
   * is invoked like this:
   * </p>
   * <pre>
   * callback.event (event,    // the specific event which fired (long)
   *                 eh,       // the event handle (int)
   *                 buffer,   // event data (String)
   *                 array     // event data (long[])
   *                 );
   * </pre>
   * <p>
   * Note that you can pass arbitrary data from the main program to the
   * callback by putting it into your {@link EventCallback callback object},
   * then accessing it in the callback via <code>this</code>.
   * </p><p>
   * This function returns an event handle which may be used to delete
   * the event.  Note that event handlers are deleted automatically when
   * the libguestfs handle is closed.
   * </p>
   *
   * @throws LibGuestFSException If there is a libguestfs error.
   * @see \"The section &quot;EVENTS&quot; in the guestfs(3) manual\"
   * @see #delete_event_callback
   * @return handle for the event
   */
  public int set_event_callback (EventCallback callback, long events)
    throws LibGuestFSException
  {
    if (g == 0)
      throw new LibGuestFSException (\"set_event_callback: handle is closed\");

    return _set_event_callback (g, callback, events);
  }

  private native int _set_event_callback (long g, EventCallback callback,
                                          long events)
    throws LibGuestFSException;

  /**
   * <p>
   * Delete an event handler.
   * </p><p>
   * Delete a previously registered event handler.  The 'eh' parameter is
   * the event handle returned from a previous call to
   * {@link #set_event_callback set_event_callback}.
   * </p><p>
   * Note that event handlers are deleted automatically when the
   * libguestfs handle is closed.
   * </p>
   *
   * @throws LibGuestFSException If there is a libguestfs error.
   * @see #set_event_callback
   */
  public void delete_event_callback (int eh)
    throws LibGuestFSException
  {
    if (g == 0)
      throw new LibGuestFSException (\"delete_event_callback: handle is closed\");

    _delete_event_callback (g, eh);
  }

  private native void _delete_event_callback (long g, int eh);

";

  (* Methods. *)
  List.iter (
    fun f ->
      let ret, args, optargs = f.style in

      if is_documented f then (
        let doc = String.replace f.longdesc "C<guestfs_" "C<g." in
        let doc =
          if optargs <> [] then
            doc ^ "\n\nOptional arguments are supplied in the final Map<String,Object> parameter, which is a hash of the argument name to its value (cast to Object).  Pass an empty Map or null for no optional arguments."
          else doc in
        let doc =
          if f.protocol_limit_warning then
            doc ^ "\n\n" ^ protocol_limit_warning
          else doc in
        let doc = pod2text ~width:60 f.name doc in
        let doc = drop_empty_trailing_lines doc in
        let doc = List.map (		(* RHBZ#501883 *)
          function
          | "" -> "</p><p>"
          | nonempty -> html_escape nonempty
        ) doc in
        let doc = String.concat "\n   * " doc in

        pr "  /**\n";
        pr "   * <p>\n";
        pr "   * %s\n" f.shortdesc;
        pr "   * </p><p>\n";
        pr "   * %s\n" doc;
        (match f.optional with
        | None -> ()
        | Some opt ->
          pr "   * </p><p>\n";
          pr "   * This function depends on the feature \"%s\".  See also {@link #feature_available}.\n"
            opt;
        );
        pr "   * </p>\n";
        (match version_added f with
        | None -> ()
        | Some version -> pr "   * @since %s\n" version
        );
        (match f with
        | { deprecated_by = Not_deprecated } -> ()
        | { deprecated_by = Replaced_by alt } ->
          (* Don't link to an undocumented function as javadoc will
           * give a hard error.
           *)
          let f_alt = Actions.find alt in
          if is_documented f_alt then
            pr "   * @deprecated In new code, use {@link #%s} instead\n" alt
          else
            pr "   * @deprecated This is replaced by method #%s which is not exported by the Java bindings\n" alt
        | { deprecated_by = Deprecated_no_replacement } ->
          pr "   * @deprecated There is no documented replacement\n"
        );
        pr "   * @throws LibGuestFSException If there is a libguestfs error.\n";
        pr "   */\n";
      );
      pr "  ";
      let deprecated =
        match f with
        | { deprecated_by = Not_deprecated } -> false
        | { deprecated_by = Replaced_by _ | Deprecated_no_replacement } ->
           true in
      generate_java_prototype ~public:true ~semicolon:false ~deprecated f.name f.style;
      pr "\n";
      pr "  {\n";
      pr "    if (g == 0)\n";
      pr "      throw new LibGuestFSException (\"%s: handle is closed\");\n"
        f.name;
      if optargs <> [] then (
        pr "\n";
        pr "    /* Unpack optional args. */\n";
        pr "    Object _optobj;\n";
        pr "    long _optargs_bitmask = 0;\n";
        List.iteri (
          fun i argt ->
            let t, boxed_t, convert, n, default =
              match argt with
              | OBool n -> "boolean", "Boolean", ".booleanValue()", n, "false"
              | OInt n -> "int", "Integer", ".intValue()", n, "0"
              | OInt64 n -> "long", "Long", ".longValue()", n, "0"
              | OString n -> "String", "String", "", n, "\"\""
              | OStringList n -> "String[]", "String[]", "", n, "new String[]{}" in
            pr "    %s %s = %s;\n" t n default;
            pr "    _optobj = null;\n";
            pr "    if (optargs != null)\n";
            pr "      _optobj = optargs.get (\"%s\");\n" n;
            pr "    if (_optobj != null) {\n";
            pr "      %s = ((%s) _optobj)%s;\n" n boxed_t convert;
            pr "      _optargs_bitmask |= %LdL;\n"
              (Int64.shift_left Int64.one i);
            pr "    }\n";
        ) optargs
      );
      pr "\n";
      (match ret with
       | RErr ->
           pr "    _%s " f.name;
           generate_java_call_args ~handle:"g" f.style;
           pr ";\n"
       | RHashtable _ ->
           pr "    String[] r = _%s " f.name;
           generate_java_call_args ~handle:"g" f.style;
           pr ";\n";
           pr "\n";
           pr "    HashMap<String, String> rhash = new HashMap<String, String> ();\n";
           pr "    for (int i = 0; i < r.length; i += 2)\n";
           pr "      rhash.put (r[i], r[i+1]);\n";
           pr "    return rhash;\n"
       | _ ->
           pr "    return _%s " f.name;
           generate_java_call_args ~handle:"g" f.style;
           pr ";\n"
      );
      pr "  }\n";
      pr "\n";

      (* Generate an overloaded method that has no optargs argument,
       * and make it call the method above with 'null' for the last
       * arg.
       *)
      if optargs <> [] then (
        pr "  ";
        generate_java_prototype ~public:true ~semicolon:false
          f.name (ret, args, []);
        pr "\n";
        pr "  {\n";
        (match ret with
        | RErr -> pr "    "
        | _ ->    pr "    return "
        );
        pr "%s (" f.name;
        List.iter (fun arg -> pr "%s, " (name_of_argt arg)) args;
        pr "null);\n";
        pr "  }\n";
        pr "\n"
      );

      (* Aliases. *)
      List.iter (
        fun alias ->
          pr "  ";
          generate_java_prototype ~public:true ~semicolon:false alias f.style;
          pr "\n";
          pr "  {\n";
          (match ret with
          | RErr -> pr "    "
          | _ ->    pr "    return "
          );
          pr "%s (" f.name;
          let needs_comma = ref false in
          List.iter (
            fun arg ->
              if !needs_comma then pr ", ";
              needs_comma := true;
              pr "%s" (name_of_argt arg)
          ) args;
          if optargs <> [] then (
            if !needs_comma then pr ", ";
            needs_comma := true;
            pr "optargs"
          );
          pr ");\n";
          pr "  }\n";
          pr "\n";

          if optargs <> [] then (
            pr "  ";
            generate_java_prototype ~public:true ~semicolon:false
              alias (ret, args, []);
            pr "\n";
            pr "  {\n";
            (match ret with
            | RErr -> pr "    "
            | _ ->    pr "    return "
            );
            pr "%s (" f.name;
            List.iter (fun arg -> pr "%s, " (name_of_argt arg)) args;
            pr "null);\n";
            pr "  }\n";
            pr "\n"
          )
      ) f.non_c_aliases;

      (* Prototype for the native method. *)
      pr "  ";
      generate_java_prototype ~privat:true ~native:true f.name f.style;
      pr "\n";
      pr "\n";
  ) (actions |> external_functions |> sort);

  pr "}\n"

(* Generate Java call arguments, eg "(handle, foo, bar)" *)
and generate_java_call_args ~handle (_, args, optargs) =
  pr "(%s" handle;
  List.iter (fun arg -> pr ", %s" (name_of_argt arg)) args;
  if optargs <> [] then (
    pr ", _optargs_bitmask";
    List.iter (fun arg -> pr ", %s" (name_of_optargt arg)) optargs
  );
  pr ")"

and generate_java_prototype ?(public=false) ?(privat=false) ?(native=false)
    ?(semicolon=true) ?(deprecated=false) name (ret, args, optargs) =
  if deprecated then pr "@Deprecated ";
  if privat then pr "private ";
  if public then pr "public ";
  if native then pr "native ";

  (* return type *)
  (match ret with
   | RErr -> pr "void ";
   | RInt _ -> pr "int ";
   | RInt64 _ -> pr "long ";
   | RBool _ -> pr "boolean ";
   | RConstString _ | RConstOptString _ | RString _
   | RBufferOut _ -> pr "String ";
   | RStringList _ -> pr "String[] ";
   | RStruct (_, typ) ->
       let name = camel_name_of_struct typ in
       pr "%s " name;
   | RStructList (_, typ) ->
       let name = camel_name_of_struct typ in
       pr "%s[] " name;
   | RHashtable _ ->
       if not native then
         pr "Map<String,String> "
       else
         pr "String[] ";
  );

  if native then pr "_%s " name else pr "%s " name;
  pr "(";
  let needs_comma = ref false in
  if native then (
    pr "long g";
    needs_comma := true
  );

  (* args *)
  List.iter (
    fun arg ->
      if !needs_comma then pr ", ";
      needs_comma := true;

      match arg with
      | String (_, n)
      | OptString n ->
          pr "String %s" n
      | BufferIn n ->
          pr "byte[] %s" n
      | StringList (_, n) ->
          pr "String[] %s" n
      | Bool n ->
          pr "boolean %s" n
      | Int n ->
          pr "int %s" n
      | Int64 n | Pointer (_, n) ->
          pr "long %s" n
  ) args;

  if optargs <> [] then (
    if !needs_comma then pr ", ";
    needs_comma := true;

    if not native then
      pr "Map<String, Object> optargs"
    else (
      pr "long _optargs_bitmask";
      List.iter (
        fun argt ->
          match argt with
          | OBool n -> pr ", boolean %s" n
          | OInt n -> pr ", int %s" n
          | OInt64 n -> pr ", long %s" n
          | OString n -> pr ", String %s" n
          | OStringList n -> pr ", String[] %s" n
      ) optargs
    )
  );

  pr ")\n";
  pr "    throws LibGuestFSException";
  if semicolon then pr ";"

and generate_java_struct jtyp cols () =
  generate_header CStyle LGPLv2plus;

  pr "\
package com.redhat.et.libguestfs;

/**
 * %s structure.
 *
 * @author rjones
 * @see GuestFS
 */
public class %s {
" jtyp jtyp;

  List.iter (
    function
    | name, FString
    | name, FUUID
    | name, FBuffer -> pr "  public String %s;\n" name
    | name, (FBytes|FUInt64|FInt64) -> pr "  public long %s;\n" name
    | name, (FUInt32|FInt32) -> pr "  public int %s;\n" name
    | name, FChar -> pr "  public char %s;\n" name
    | name, FOptPercent ->
        pr "  /* The next field is [0..100] or -1 meaning 'not present': */\n";
        pr "  public float %s;\n" name
  ) cols;

  pr "}\n"

and generate_java_c actions () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <config.h>

/* It is safe to call deprecated functions from this file. */
#define GUESTFS_NO_WARN_DEPRECATED
#undef GUESTFS_NO_DEPRECATED

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>

#include \"com_redhat_et_libguestfs_GuestFS.h\"
#include \"guestfs.h\"
#include \"guestfs-utils.h\"
#include \"structs-cleanups.h\"

/* Note that this function returns.  The exception is not thrown
 * until after the wrapper function returns.
 */
static void
throw_exception (JNIEnv *env, const char *msg)
{
  jclass cl;
  cl = (*env)->FindClass (env,
                          \"com/redhat/et/libguestfs/LibGuestFSException\");
  (*env)->ThrowNew (env, cl, msg);
}

/* Note that this function returns.  The exception is not thrown
 * until after the wrapper function returns.
 */
static void
throw_out_of_memory (JNIEnv *env, const char *msg)
{
  jclass cl;
  cl = (*env)->FindClass (env,
                          \"com/redhat/et/libguestfs/LibGuestFSOutOfMemory\");
  (*env)->ThrowNew (env, cl, msg);
}
";

  List.iter (
    fun { name; style = (ret, args, optargs as style);
          c_function = c_function } ->
      pr "\n";
      pr "JNIEXPORT ";
      (match ret with
       | RErr -> pr "void ";
       | RInt _ -> pr "jint ";
       | RInt64 _ -> pr "jlong ";
       | RBool _ -> pr "jboolean ";
       | RConstString _ | RConstOptString _ | RString _
       | RBufferOut _ -> pr "jstring ";
       | RStruct _ | RHashtable _ ->
           pr "jobject ";
       | RStringList _ | RStructList _ ->
           pr "jobjectArray ";
      );
      pr "JNICALL\n";
      pr "Java_com_redhat_et_libguestfs_GuestFS_";
      pr "%s" (String.replace ("_" ^ name) "_" "_1");
      pr "  (JNIEnv *env, jobject obj, jlong jg";
      List.iter (
        function
        | String (_, n)
        | OptString n ->
            pr ", jstring j%s" n
        | BufferIn n ->
            pr ", jbyteArray j%s" n
        | StringList (_, n) ->
            pr ", jobjectArray j%s" n
        | Bool n ->
            pr ", jboolean j%s" n
        | Int n ->
            pr ", jint j%s" n
        | Int64 n | Pointer (_, n) ->
            pr ", jlong j%s" n
      ) args;
      if optargs <> [] then (
        pr ", jlong joptargs_bitmask";
        List.iter (
          function
          | OBool n -> pr ", jboolean j%s" n
          | OInt n -> pr ", jint j%s" n
          | OInt64 n -> pr ", jlong j%s" n
          | OString n -> pr ", jstring j%s" n
          | OStringList n -> pr ", jobjectArray j%s" n
        ) optargs
      );
      pr ")\n";
      pr "{\n";
      pr "  guestfs_h *g = (guestfs_h *) (long) jg;\n";
      (match ret with
       | RErr -> pr "  int r;\n"
       | RBool _
       | RInt _ -> pr "  int r;\n"
       | RInt64 _ -> pr "  int64_t r;\n"
       | RConstString _ -> pr "  const char *r;\n"
       | RConstOptString _ -> pr "  const char *r;\n"
       | RString _ ->
           pr "  jstring jr;\n";
           pr "  char *r;\n"
       | RStringList _
       | RHashtable _ ->
           pr "  jobjectArray jr;\n";
           pr "  size_t r_len;\n";
           pr "  jclass cl;\n";
           pr "  jstring jstr;\n";
           pr "  char **r;\n"
       | RStruct (_, typ) ->
           pr "  jobject jr;\n";
           pr "  jclass cl;\n";
           pr "  jfieldID fl;\n";
           pr "  CLEANUP_FREE_%s struct guestfs_%s *r = NULL;\n"
             (String.uppercase_ascii typ) typ
       | RStructList (_, typ) ->
           pr "  jobjectArray jr;\n";
           pr "  jclass cl;\n";
           pr "  jfieldID fl;\n";
           pr "  jobject jfl;\n";
           pr "  CLEANUP_FREE_%s_LIST struct guestfs_%s_list *r = NULL;\n"
             (String.uppercase_ascii typ) typ
       | RBufferOut _ ->
           pr "  jstring jr;\n";
           pr "  char *r;\n";
           pr "  size_t size;\n"
      );

      List.iter (
        function
        | String (_, n)
        | OptString n ->
            pr "  const char *%s;\n" n
        | BufferIn n ->
            pr "  char *%s;\n" n;
            pr "  size_t %s_size;\n" n
        | StringList (_, n) ->
            pr "  size_t %s_len;\n" n;
            pr "  CLEANUP_FREE char **%s = NULL;\n" n
        | Bool n
        | Int n ->
            pr "  int %s;\n" n
        | Int64 n ->
            pr "  int64_t %s;\n" n
        | Pointer (t, n) ->
            pr "  void * /* %s */ %s;\n" t n
      ) args;

      if optargs <> [] then (
        pr "  struct %s optargs_s;\n" c_function;
        pr "  const struct %s *optargs = &optargs_s;\n" c_function;

        List.iter (
          function
          | OBool _ | OInt _ | OInt64 _ | OString _ -> ()
          | OStringList n ->
            pr "  size_t %s_len;\n" n;
            pr "  CLEANUP_FREE char **%s = NULL;\n" n
        ) optargs
      );

      let needs_i =
        (match ret with
         | RStringList _ | RStructList _ | RHashtable _ -> true
         | RErr | RBool _ | RInt _ | RInt64 _ | RConstString _
         | RConstOptString _
         | RString _ | RBufferOut _ | RStruct _ -> false) ||
          List.exists (function
          | StringList _ -> true
          | _ -> false) args ||
          List.exists (function
          | OStringList _ -> true
          | _ -> false) optargs in
      if needs_i then
        pr "  size_t i;\n";

      pr "\n";

      (* Get the parameters. *)
      let add_ret_error_label = ref false in
      List.iter (
        function
        | String (_, n) ->
            pr "  %s = (*env)->GetStringUTFChars (env, j%s, NULL);\n" n n
        | OptString n ->
            (* This is completely undocumented, but Java null becomes
             * a NULL parameter.
             *)
            pr "  %s = j%s ? (*env)->GetStringUTFChars (env, j%s, NULL) : NULL;\n" n n n
        | BufferIn n ->
            pr "  %s = (char *) (*env)->GetByteArrayElements (env, j%s, NULL);\n" n n;
            pr "  %s_size = (*env)->GetArrayLength (env, j%s);\n" n n
        | StringList (_, n) ->
            pr "  %s_len = (*env)->GetArrayLength (env, j%s);\n" n n;
            pr "  %s = malloc (sizeof (char *) * (%s_len+1));\n" n n;
            pr "  if (%s == NULL) {\n" n;
            pr "    throw_out_of_memory (env, \"malloc\");\n";
            pr "    goto ret_error;\n";
            add_ret_error_label := true;
            pr "  }\n";
            pr "  for (i = 0; i < %s_len; ++i) {\n" n;
            pr "    jobject o = (*env)->GetObjectArrayElement (env, j%s, i);\n"
              n;
            pr "    %s[i] = (char *) (*env)->GetStringUTFChars (env, o, NULL);\n" n;
            pr "  }\n";
            pr "  %s[%s_len] = NULL;\n" n n;
        | Bool n
        | Int n
        | Int64 n ->
            pr "  %s = j%s;\n" n n
        | Pointer (t, n) ->
            pr "  %s = POINTER_NOT_IMPLEMENTED (\"%s\");\n" n t
      ) args;

      if optargs <> [] then (
        pr "\n";
        List.iter (
          function
          | OBool n | OInt n | OInt64 n ->
              pr "  optargs_s.%s = j%s;\n" n n
          | OString n ->
              pr "  optargs_s.%s = (*env)->GetStringUTFChars (env, j%s, NULL);\n"
                n n
          | OStringList n ->
            pr "  %s_len = (*env)->GetArrayLength (env, j%s);\n" n n;
            pr "  %s = malloc (sizeof (char *) * (%s_len+1));\n" n n;
            pr "  if (%s == NULL) {\n" n;
            pr "    throw_out_of_memory (env, \"malloc\");\n";
            pr "    goto ret_error;\n";
            add_ret_error_label := true;
            pr "  }\n";
            pr "  for (i = 0; i < %s_len; ++i) {\n" n;
            pr "    jobject o = (*env)->GetObjectArrayElement (env, j%s, i);\n"
              n;
            pr "    %s[i] = (char *) (*env)->GetStringUTFChars (env, o, NULL);\n" n;
            pr "  }\n";
            pr "  %s[%s_len] = NULL;\n" n n;
            pr "  optargs_s.%s = %s;\n" n n
        ) optargs;
        pr "  optargs_s.bitmask = joptargs_bitmask;\n";
      );

      pr "\n";

      (* Make the call. *)
      pr "  r = %s " c_function;
      generate_c_call_args ~handle:"g" style;
      pr ";\n";

      pr "\n";

      (* Release the parameters. *)
      List.iter (
        function
        | String (_, n) ->
            pr "  (*env)->ReleaseStringUTFChars (env, j%s, %s);\n" n n
        | OptString n ->
            pr "  if (j%s)\n" n;
            pr "    (*env)->ReleaseStringUTFChars (env, j%s, %s);\n" n n
        | BufferIn n ->
            pr "  (*env)->ReleaseByteArrayElements (env, j%s, (jbyte *) %s, 0);\n" n n
        | StringList (_, n) ->
            pr "  for (i = 0; i < %s_len; ++i) {\n" n;
            pr "    jobject o = (*env)->GetObjectArrayElement (env, j%s, i);\n"
              n;
            pr "    (*env)->ReleaseStringUTFChars (env, o, %s[i]);\n" n;
            pr "  }\n";
        | Bool _
        | Int _
        | Int64 _
        | Pointer _ -> ()
      ) args;

      List.iter (
        function
        | OBool n | OInt n | OInt64 n -> ()
        | OString n ->
            pr "  (*env)->ReleaseStringUTFChars (env, j%s, optargs_s.%s);\n" n n
        | OStringList n ->
            pr "  for (i = 0; i < %s_len; ++i) {\n" n;
            pr "    jobject o = (*env)->GetObjectArrayElement (env, j%s, i);\n"
              n;
            pr "    (*env)->ReleaseStringUTFChars (env, o, optargs_s.%s[i]);\n" n;
            pr "  }\n";
      ) optargs;

      pr "\n";

      (* Check for errors. *)
      (match errcode_of_ret ret with
       | `CannotReturnError -> ()
       | (`ErrorIsMinusOne|`ErrorIsNULL) as errcode ->
           (match errcode with
            | `ErrorIsMinusOne ->
                pr "  if (r == -1) {\n";
            | `ErrorIsNULL ->
                pr "  if (r == NULL) {\n";
           );
           pr "    throw_exception (env, guestfs_last_error (g));\n";
           pr "    goto ret_error;\n";
           add_ret_error_label := true;
           pr "  }\n"
      );

      (* Return value. *)
      (match ret with
       | RErr -> pr "  return;\n";
       | RInt _ -> pr "  return (jint) r;\n"
       | RBool _ -> pr "  return (jboolean) r;\n"
       | RInt64 _ -> pr "  return (jlong) r;\n"
       | RConstString _ -> pr "  return (*env)->NewStringUTF (env, r);\n"
       | RConstOptString _ ->
           pr "  return (*env)->NewStringUTF (env, r); /* XXX r NULL? */\n"
       | RString _ ->
           pr "  jr = (*env)->NewStringUTF (env, r);\n";
           pr "  free (r);\n";
           pr "  return jr;\n"
       | RStringList _
       | RHashtable _ ->
           pr "  for (r_len = 0; r[r_len] != NULL; ++r_len) ;\n";
           pr "  cl = (*env)->FindClass (env, \"java/lang/String\");\n";
           pr "  jstr = (*env)->NewStringUTF (env, \"\");\n";
           pr "  jr = (*env)->NewObjectArray (env, r_len, cl, jstr);\n";
           pr "  for (i = 0; i < r_len; ++i) {\n";
           pr "    jstr = (*env)->NewStringUTF (env, r[i]);\n";
           pr "    (*env)->SetObjectArrayElement (env, jr, i, jstr);\n";
           pr "    free (r[i]);\n";
           pr "  }\n";
           pr "  free (r);\n";
           pr "  return jr;\n"
       | RStruct (_, typ) ->
           let jtyp = camel_name_of_struct typ in
           let cols = cols_of_struct typ in
           generate_java_struct_return typ jtyp cols
       | RStructList (_, typ) ->
           let jtyp = camel_name_of_struct typ in
           let cols = cols_of_struct typ in
           generate_java_struct_list_return typ jtyp cols
       | RBufferOut _ ->
           pr "  jr = (*env)->NewStringUTF (env, r); // XXX size\n";
           pr "  free (r);\n";
           pr "  return jr;\n"
      );

      if !add_ret_error_label then (
        pr "\n";
        pr " ret_error:\n";
        (match ret with
         | RErr ->
            pr "  return;\n"
         | RInt _
         | RInt64 _
         | RBool _ ->
            pr "  return -1;\n"
         | RConstString _ | RConstOptString _ | RString _
         | RBufferOut _
         | RStruct _ | RHashtable _
         | RStringList _ | RStructList _ ->
            pr "  return NULL;\n"
        );
      );

      pr "}\n";
      pr "\n"
  ) (actions |> external_functions |> sort)

and generate_java_struct_return typ jtyp cols =
  pr "  cl = (*env)->FindClass (env, \"com/redhat/et/libguestfs/%s\");\n" jtyp;
  pr "  jr = (*env)->AllocObject (env, cl);\n";
  List.iter (
    function
    | name, FString ->
        pr "  fl = (*env)->GetFieldID (env, cl, \"%s\", \"Ljava/lang/String;\");\n" name;
        pr "  (*env)->SetObjectField (env, jr, fl, (*env)->NewStringUTF (env, r->%s));\n" name;
    | name, FUUID ->
        pr "  {\n";
        pr "    char s[33];\n";
        pr "    memcpy (s, r->%s, 32);\n" name;
        pr "    s[32] = 0;\n";
        pr "    fl = (*env)->GetFieldID (env, cl, \"%s\", \"Ljava/lang/String;\");\n" name;
        pr "    (*env)->SetObjectField (env, jr, fl, (*env)->NewStringUTF (env, s));\n";
        pr "  }\n";
    | name, FBuffer ->
        pr "  {\n";
        pr "    size_t len = r->%s_len;\n" name;
        pr "    CLEANUP_FREE char *s = malloc (len + 1);\n";
        pr "    if (s == NULL) {\n";
        pr "      throw_out_of_memory (env, \"malloc\");\n";
        pr "      goto ret_error;\n";
        pr "    }\n";
        pr "    memcpy (s, r->%s, len);\n" name;
        pr "    s[len] = 0;\n";
        pr "    fl = (*env)->GetFieldID (env, cl, \"%s\", \"Ljava/lang/String;\");\n" name;
        pr "    (*env)->SetObjectField (env, jr, fl, (*env)->NewStringUTF (env, s));\n";
        pr "  }\n";
    | name, (FBytes|FUInt64|FInt64) ->
        pr "  fl = (*env)->GetFieldID (env, cl, \"%s\", \"J\");\n" name;
        pr "  (*env)->SetLongField (env, jr, fl, r->%s);\n" name;
    | name, (FUInt32|FInt32) ->
        pr "  fl = (*env)->GetFieldID (env, cl, \"%s\", \"I\");\n" name;
        pr "  (*env)->SetIntField (env, jr, fl, r->%s);\n" name;
    | name, FOptPercent ->
        pr "  fl = (*env)->GetFieldID (env, cl, \"%s\", \"F\");\n" name;
        pr "  (*env)->SetFloatField (env, jr, fl, r->%s);\n" name;
    | name, FChar ->
        pr "  fl = (*env)->GetFieldID (env, cl, \"%s\", \"C\");\n" name;
        pr "  (*env)->SetCharField (env, jr, fl, r->%s);\n" name;
  ) cols;
  pr "  return jr;\n"

and generate_java_struct_list_return typ jtyp cols =
  pr "  cl = (*env)->FindClass (env, \"com/redhat/et/libguestfs/%s\");\n" jtyp;
  pr "  jr = (*env)->NewObjectArray (env, r->len, cl, NULL);\n";
  pr "\n";
  pr "  for (i = 0; i < r->len; ++i) {\n";
  pr "    jfl = (*env)->AllocObject (env, cl);\n";
  pr "\n";
  List.iter (
    fun (name, ftyp) ->
      (* Get the field ID in 'fl'. *)
      let java_field_type = match ftyp with
        | FString | FUUID | FBuffer -> "Ljava/lang/String;"
        | FBytes | FUInt64 | FInt64 -> "J"
        | FUInt32 | FInt32 -> "I"
        | FOptPercent -> "F"
        | FChar -> "C" in
      pr "    fl = (*env)->GetFieldID (env, cl, \"%s\",\n" name;
      pr "                             \"%s\");\n" java_field_type;

      (* Assign the value to this field. *)
      match ftyp with
      | FString ->
        pr "    (*env)->SetObjectField (env, jfl, fl,\n";
        pr "                            (*env)->NewStringUTF (env, r->val[i].%s));\n" name;
      | FUUID ->
        pr "    {\n";
        pr "      char s[33];\n";
        pr "      memcpy (s, r->val[i].%s, 32);\n" name;
        pr "      s[32] = 0;\n";
        pr "      (*env)->SetObjectField (env, jfl, fl,\n";
        pr "                              (*env)->NewStringUTF (env, s));\n";
        pr "    }\n";
      | FBuffer ->
        pr "    {\n";
        pr "      size_t len = r->val[i].%s_len;\n" name;
        pr "      CLEANUP_FREE char *s = malloc (len + 1);\n";
        pr "      if (s == NULL) {\n";
        pr "        throw_out_of_memory (env, \"malloc\");\n";
        pr "        goto ret_error;\n";
        pr "      }\n";
        pr "      memcpy (s, r->val[i].%s, len);\n" name;
        pr "      s[len] = 0;\n";
        pr "      (*env)->SetObjectField (env, jfl, fl,\n";
        pr "                              (*env)->NewStringUTF (env, s));\n";
        pr "    }\n";
      | FBytes|FUInt64|FInt64 ->
        pr "    (*env)->SetLongField (env, jfl, fl, r->val[i].%s);\n" name;
      | FUInt32|FInt32 ->
        pr "    (*env)->SetIntField (env, jfl, fl, r->val[i].%s);\n" name;
      | FOptPercent ->
        pr "    (*env)->SetFloatField (env, jfl, fl, r->val[i].%s);\n" name;
      | FChar ->
        pr "    (*env)->SetCharField (env, jfl, fl, r->val[i].%s);\n" name;
  ) cols;
  pr "\n";
  pr "    (*env)->SetObjectArrayElement (env, jr, i, jfl);\n";
  pr "  }\n";
  pr "\n";
  pr "  return jr;\n"

and generate_java_makefile_inc () =
  generate_header HashStyle GPLv2plus;

  let jtyps = List.map (fun { s_camel_name = jtyp } -> jtyp) external_structs in
  let jtyps = List.sort compare jtyps in

  pr "java_built_sources = \\\n";
  List.iter (
    pr "\tcom/redhat/et/libguestfs/%s.java \\\n"
  ) jtyps;
  pr "\tcom/redhat/et/libguestfs/GuestFS.java\n"

and generate_java_gitignore () =
  let jtyps = List.map (fun { s_camel_name = jtyp } -> jtyp) external_structs in
  let jtyps = List.sort compare jtyps in

  List.iter (pr "%s.java\n") jtyps
