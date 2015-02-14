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
open Events
open C

(* Generate Java bindings GuestFS.java file. *)
let rec generate_java_java () =
  generate_header CStyle LGPLv2plus;

  pr "\
package com.redhat.et.libguestfs;

import java.util.HashMap;
import java.util.Map;

/**
 * Libguestfs handle.
 * <p>
 * The <code>GuestFS</code> object corresponds to a libguestfs handle.
 * <p>
 * Note that the main documentation for the libguestfs API is in
 * the following man pages:
 * <p>
 * <ol>
 * <li> <a href=\"http://libguestfs.org/guestfs-java.3.html\"><code>guestfs-java(3)</code></a> and </li>
 * <li> <a href=\"http://libguestfs.org/guestfs.3.html\"><code>guestfs(3)</code></a>. </li>
 * </ol>
 * <p>
 * This javadoc is <b>not</b> a good introduction to using libguestfs.
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
   * @throws LibGuestFSException
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
   * @throws LibGuestFSException
   */
  public GuestFS () throws LibGuestFSException
  {
    g = _create (0);
  }

  private native long _create (int flags) throws LibGuestFSException;

  /**
   * Close a libguestfs handle.
   *
   * You can also leave handles to be collected by the garbage
   * collector, but this method ensures that the resources used
   * by the handle are freed up immediately.  If you call any
   * other methods after closing the handle, you will get an
   * exception.
   *
   * @throws LibGuestFSException
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
      pr "  public static final long EVENT_%s = 0x%x;\n" (String.uppercase name) bitmask;
      pr "\n";
  ) events;

  pr "  /** Bitmask of all events. */\n";
  pr "  public static final long EVENT_ALL = 0x%x;\n" all_events_bitmask;
  pr "\n";

  pr "\
  /** Utility function to turn an event number or bitmask into a string. */
  public static String eventToString (long events)
  {
    return _event_to_string (events);
  }

  private static native String _event_to_string (long events);

  /**
   * Set an event handler.
   * <p>
   * Set an event handler (<code>callback</code>) which is called when any
   * event from the set (<code>events</code>) is raised by the API.
   * <code>events</code> is one or more <code>EVENT_*</code> constants,
   * bitwise ORed together.
   * <p>
   * When an event happens, the callback object's <code>event</code> method
   * is invoked like this:
   * <pre>
   * callback.event (event,    // the specific event which fired (long)
   *                 eh,       // the event handle (int)
   *                 buffer,   // event data (String)
   *                 array     // event data (long[])
   *                 );
   * </pre>
   * Note that you can pass arbitrary data from the main program to the
   * callback by putting it into your {@link EventCallback callback object},
   * then accessing it in the callback via <code>this</code>.
   * <p>
   * This function returns an event handle which may be used to delete
   * the event.  Note that event handlers are deleted automatically when
   * the libguestfs handle is closed.
   *
   * @throws LibGuestFSException
   * @see The section \"EVENTS\" in the guestfs(3) manual
   * @see #delete_event_callback
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
   * Delete an event handler.
   * <p>
   * Delete a previously registered event handler.  The 'eh' parameter is
   * the event handle returned from a previous call to
   * {@link #set_event_callback set_event_callback}.
   * <p>
   * Note that event handlers are deleted automatically when the
   * libguestfs handle is closed.
   *
   * @throws LibGuestFSException
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
        let doc = replace_str f.longdesc "C<guestfs_" "C<g." in
        let doc =
          if optargs <> [] then
            doc ^ "\n\nOptional arguments are supplied in the final Map<String,Object> parameter, which is a hash of the argument name to its value (cast to Object).  Pass an empty Map or null for no optional arguments."
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
        let doc = List.map (		(* RHBZ#501883 *)
          function
          | "" -> "<p>"
          | nonempty -> nonempty
        ) doc in
        let doc = String.concat "\n   * " doc in

        pr "  /**\n";
        pr "   * %s\n" f.shortdesc;
        pr "   * <p>\n";
        pr "   * %s\n" doc;
        pr "   * @throws LibGuestFSException\n";
        pr "   */\n";
      );
      pr "  ";
      generate_java_prototype ~public:true ~semicolon:false f.name f.style;
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
        iteri (
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
  ) external_functions_sorted;

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
    ?(semicolon=true) name (ret, args, optargs) =
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
      | Pathname n
      | Device n | Mountable n | Dev_or_Path n | Mountable_or_Path n
      | String n
      | OptString n
      | FileIn n
      | FileOut n
      | Key n
      | GUID n ->
          pr "String %s" n
      | BufferIn n ->
          pr "byte[] %s" n
      | StringList n | DeviceList n ->
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

and generate_java_c () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>

#include \"com_redhat_et_libguestfs_GuestFS.h\"
#include \"guestfs.h\"
#include \"guestfs-internal-frontend.h\"

/* This is the opaque data passed between _set_event_callback and
 * the C wrapper which calls the Java event callback.
 *
 * NB: The 'callback' in the following struct is registered as a global
 * reference.  It must be freed along with the struct.
 */
struct callback_data {
  JavaVM *jvm;           // JVM
  jobject callback;      // object supporting EventCallback interface
  jmethodID method;      // callback.event method
};

static struct callback_data **get_all_event_callbacks (guestfs_h *g, size_t *len_rtn);

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

JNIEXPORT jlong JNICALL
Java_com_redhat_et_libguestfs_GuestFS__1create (JNIEnv *env,
                                                jobject obj_unused, jint flags)
{
  guestfs_h *g;

  g = guestfs_create_flags ((int) flags);
  if (g == NULL) {
    throw_exception (env, \"GuestFS.create: failed to allocate handle\");
    return 0;
  }
  guestfs_set_error_handler (g, NULL, NULL);
  return (jlong) (long) g;
}

JNIEXPORT void JNICALL
Java_com_redhat_et_libguestfs_GuestFS__1close
  (JNIEnv *env, jobject obj, jlong jg)
{
  guestfs_h *g = (guestfs_h *) (long) jg;
  size_t len, i;
  struct callback_data **data;

  /* There is a nasty, difficult to solve case here where the
   * user deletes events in one of the callbacks that we are
   * about to invoke, resulting in a double-free.  XXX
   */
  data = get_all_event_callbacks (g, &len);

  guestfs_close (g);

  for (i = 0; i < len; ++i) {
    (*env)->DeleteGlobalRef (env, data[i]->callback);
    free (data[i]);
  }
  free (data);
}

/* See EventCallback interface. */
#define METHOD_NAME \"event\"
#define METHOD_SIGNATURE \"(JILjava/lang/String;[J)V\"

static void
guestfs_java_callback (guestfs_h *g,
                       void *opaque,
                       uint64_t event,
                       int event_handle,
                       int flags,
                       const char *buf, size_t buf_len,
                       const uint64_t *array, size_t array_len)
{
  struct callback_data *data = opaque;
  JavaVM *jvm = data->jvm;
  JNIEnv *env;
  int r;
  jstring jbuf;
  jlongArray jarray;
  size_t i;
  jlong jl;

  /* Get the Java environment.  See:
   * http://stackoverflow.com/questions/12900695/how-to-obtain-jni-interface-pointer-jnienv-for-asynchronous-calls
   */
  r = (*jvm)->GetEnv (jvm, (void **) &env, JNI_VERSION_1_6);
  if (r != JNI_OK) {
    switch (r) {
    case JNI_EDETACHED:
      /* This can happen when the close event is generated during an atexit
       * cleanup.  The JVM has probably been destroyed so I doubt it is
       * safe to run Java code at this point.
       */
      fprintf (stderr, \"%%s: event %%\" PRIu64 \" (eh %%d) ignored because the thread is not attached to the JVM.  This can happen when libguestfs handles are cleaned up at program exit after the JVM has been destroyed.\\n\",
               __func__, event, event_handle);
      return;

    case JNI_EVERSION:
      fprintf (stderr, \"%%s: event %%\" PRIu64 \" (eh %%d) failed because the JVM version is too old.  JVM >= 1.6 is required.\\n\",
               __func__, event, event_handle);
      return;

    default:
      fprintf (stderr, \"%%s: jvm->GetEnv failed! (JNI_* error code = %%d)\\n\",
               __func__, r);
      return;
    }
  }

  /* Convert the buffer and array to Java objects. */
  jbuf = (*env)->NewStringUTF (env, buf); // XXX size

  jarray = (*env)->NewLongArray (env, array_len);
  for (i = 0; i < array_len; ++i) {
    jl = array[i];
    (*env)->SetLongArrayRegion (env, jarray, i, 1, &jl);
  }

  /* Call the event method.  If it throws an exception, all we can do is
   * print it on stderr.
   */
  (*env)->ExceptionClear (env);
  (*env)->CallVoidMethod (env, data->callback, data->method,
                          (jlong) event, (jint) event_handle,
                          jbuf, jarray);
  if ((*env)->ExceptionOccurred (env)) {
    (*env)->ExceptionDescribe (env);
    (*env)->ExceptionClear (env);
  }
}

JNIEXPORT jint JNICALL
Java_com_redhat_et_libguestfs_GuestFS__1set_1event_1callback
  (JNIEnv *env, jobject obj, jlong jg, jobject jcallback, jlong jevents)
{
  guestfs_h *g = (guestfs_h *) (long) jg;
  int r;
  struct callback_data *data;
  jclass callback_class;
  jmethodID method;
  char key[64];

  callback_class = (*env)->GetObjectClass (env, jcallback);
  method = (*env)->GetMethodID (env, callback_class, METHOD_NAME, METHOD_SIGNATURE);
  if (method == 0) {
    throw_exception (env, \"GuestFS.set_event_callback: callback class does not implement the EventCallback interface\");
    return -1;
  }

  data = guestfs_int_safe_malloc (g, sizeof *data);
  (*env)->GetJavaVM (env, &data->jvm);
  data->method = method;

  r = guestfs_set_event_callback (g, guestfs_java_callback,
                                  (uint64_t) jevents, 0, data);
  if (r == -1) {
    free (data);
    throw_exception (env, guestfs_last_error (g));
    return -1;
  }

  /* Register jcallback as a global reference so the GC won't free it. */
  data->callback = (*env)->NewGlobalRef (env, jcallback);

  /* Store 'data' in the handle, so we can free it at some point. */
  snprintf (key, sizeof key, \"_java_event_%%d\", r);
  guestfs_set_private (g, key, data);

  return (jint) r;
}

JNIEXPORT void JNICALL
Java_com_redhat_et_libguestfs_GuestFS__1delete_1event_1callback
  (JNIEnv *env, jobject obj, jlong jg, jint eh)
{
  guestfs_h *g = (guestfs_h *) (long) jg;
  char key[64];
  struct callback_data *data;

  snprintf (key, sizeof key, \"_java_event_%%d\", eh);

  data = guestfs_get_private (g, key);
  if (data) {
    (*env)->DeleteGlobalRef (env, data->callback);
    free (data);
    guestfs_set_private (g, key, NULL);
    guestfs_delete_event_callback (g, eh);
  }
}

JNIEXPORT jstring JNICALL
Java_com_redhat_et_libguestfs_GuestFS__1event_1to_1string
  (JNIEnv *env, jclass cl, jlong jevents)
{
  uint64_t events = (uint64_t) jevents;
  char *str;
  jstring jr;

  str = guestfs_event_to_string (events);
  if (str == NULL) {
    perror (\"guestfs_event_to_string\");
    return NULL;
  }

  jr = (*env)->NewStringUTF (env, str);
  free (str);

  return jr;
}

static struct callback_data **
get_all_event_callbacks (guestfs_h *g, size_t *len_rtn)
{
  struct callback_data **r;
  size_t i;
  const char *key;
  struct callback_data *data;

  /* Count the length of the array that will be needed. */
  *len_rtn = 0;
  data = guestfs_first_private (g, &key);
  while (data != NULL) {
    if (strncmp (key, \"_java_event_\", strlen (\"_java_event_\")) == 0)
      (*len_rtn)++;
    data = guestfs_next_private (g, &key);
  }

  /* Copy them into the return array. */
  r = guestfs_int_safe_malloc (g, sizeof (struct callback_data *) * (*len_rtn));

  i = 0;
  data = guestfs_first_private (g, &key);
  while (data != NULL) {
    if (strncmp (key, \"_java_event_\", strlen (\"_java_event_\")) == 0) {
      r[i] = data;
      i++;
    }
    data = guestfs_next_private (g, &key);
  }

  return r;
}

";

  List.iter (
    fun { name = name; style = (ret, args, optargs as style);
          c_function = c_function } ->
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
      pr "%s" (replace_str ("_" ^ name) "_" "_1");
      pr "  (JNIEnv *env, jobject obj, jlong jg";
      List.iter (
        function
        | Pathname n
        | Device n | Mountable n | Dev_or_Path n | Mountable_or_Path n
        | String n
        | OptString n
        | FileIn n
        | FileOut n
        | Key n
        | GUID n ->
            pr ", jstring j%s" n
        | BufferIn n ->
            pr ", jbyteArray j%s" n
        | StringList n | DeviceList n ->
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
           pr "  struct guestfs_%s *r;\n" typ
       | RStructList (_, typ) ->
           pr "  jobjectArray jr;\n";
           pr "  jclass cl;\n";
           pr "  jfieldID fl;\n";
           pr "  jobject jfl;\n";
           pr "  struct guestfs_%s_list *r;\n" typ
       | RBufferOut _ ->
           pr "  jstring jr;\n";
           pr "  char *r;\n";
           pr "  size_t size;\n"
      );

      List.iter (
        function
        | Pathname n
        | Device n | Mountable n | Dev_or_Path n | Mountable_or_Path n
        | String n
        | OptString n
        | FileIn n
        | FileOut n
        | Key n
        | GUID n ->
            pr "  const char *%s;\n" n
        | BufferIn n ->
            pr "  char *%s;\n" n;
            pr "  size_t %s_size;\n" n
        | StringList n | DeviceList n ->
            pr "  size_t %s_len;\n" n;
            pr "  char **%s;\n" n
        | Bool n
        | Int n ->
            pr "  int %s;\n" n
        | Int64 n ->
            pr "  int64_t %s;\n" n
        | Pointer (t, n) ->
            pr "  %s %s;\n" t n
      ) args;

      if optargs <> [] then (
        pr "  struct %s optargs_s;\n" c_function;
        pr "  const struct %s *optargs = &optargs_s;\n" c_function;

        List.iter (
          function
          | OBool _ | OInt _ | OInt64 _ | OString _ -> ()
          | OStringList n ->
            pr "  size_t %s_len;\n" n;
            pr "  char **%s;\n" n
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
          | DeviceList _ -> true
          | _ -> false) args ||
          List.exists (function
          | OStringList _ -> true
          | _ -> false) optargs in
      if needs_i then
        pr "  size_t i;\n";

      pr "\n";

      (* Get the parameters. *)
      List.iter (
        function
        | Pathname n
        | Device n | Mountable n | Dev_or_Path n | Mountable_or_Path n
        | String n
        | FileIn n
        | FileOut n
        | Key n
        | GUID n ->
            pr "  %s = (*env)->GetStringUTFChars (env, j%s, NULL);\n" n n
        | OptString n ->
            (* This is completely undocumented, but Java null becomes
             * a NULL parameter.
             *)
            pr "  %s = j%s ? (*env)->GetStringUTFChars (env, j%s, NULL) : NULL;\n" n n n
        | BufferIn n ->
            pr "  %s = (char *) (*env)->GetByteArrayElements (env, j%s, NULL);\n" n n;
            pr "  %s_size = (*env)->GetArrayLength (env, j%s);\n" n n
        | StringList n | DeviceList n ->
            pr "  %s_len = (*env)->GetArrayLength (env, j%s);\n" n n;
            pr "  %s = guestfs_int_safe_malloc (g, sizeof (char *) * (%s_len+1));\n" n n;
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
            pr "  %s = (%s) j%s;\n" n t n
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
            pr "  %s = guestfs_int_safe_malloc (g, sizeof (char *) * (%s_len+1));\n" n n;
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
        | Pathname n
        | Device n | Mountable n | Dev_or_Path n | Mountable_or_Path n
        | String n
        | FileIn n
        | FileOut n
        | Key n
        | GUID n ->
            pr "  (*env)->ReleaseStringUTFChars (env, j%s, %s);\n" n n
        | OptString n ->
            pr "  if (j%s)\n" n;
            pr "    (*env)->ReleaseStringUTFChars (env, j%s, %s);\n" n n
        | BufferIn n ->
            pr "  (*env)->ReleaseByteArrayElements (env, j%s, (jbyte *) %s, 0);\n" n n
        | StringList n | DeviceList n ->
            pr "  for (i = 0; i < %s_len; ++i) {\n" n;
            pr "    jobject o = (*env)->GetObjectArrayElement (env, j%s, i);\n"
              n;
            pr "    (*env)->ReleaseStringUTFChars (env, o, %s[i]);\n" n;
            pr "  }\n";
            pr "  free (%s);\n" n
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
            pr "  free (%s);\n" n
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
           (match ret with
            | RErr ->
                pr "    return;\n"
            | RInt _
            | RInt64 _
            | RBool _ ->
                pr "    return -1;\n"
            | RConstString _ | RConstOptString _ | RString _
            | RBufferOut _
            | RStruct _ | RHashtable _
            | RStringList _ | RStructList _ ->
                pr "    return NULL;\n"
           );
           pr "  }\n"
      );

      (* Return value. *)
      (match ret with
       | RErr -> ()
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

      pr "}\n";
      pr "\n"
  ) external_functions_sorted

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
        pr "    char s[len+1];\n";
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
  pr "  free (r);\n";
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
        pr "      char s[len+1];\n";
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
  pr "  guestfs_free_%s_list (r);\n" typ;
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
