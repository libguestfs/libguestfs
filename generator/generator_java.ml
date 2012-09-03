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

(* Generate Java bindings GuestFS.java file. *)
let rec generate_java_java () =
  generate_header CStyle LGPLv2plus;

  pr "\
package com.redhat.et.libguestfs;

import java.util.HashMap;
import java.util.Map;

/**
 * The GuestFS object is a libguestfs handle.
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

  /**
   * Create a libguestfs handle.
   *
   * @throws LibGuestFSException
   */
  public GuestFS () throws LibGuestFSException
  {
    g = _create ();
  }
  private native long _create () throws LibGuestFSException;

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

  List.iter (
    fun (name, (ret, args, optargs as style), _, flags, _, shortdesc, longdesc) ->
      if not (List.mem NotInDocs flags); then (
        let doc = replace_str longdesc "C<guestfs_" "C<g." in
        let doc =
          if optargs <> [] then
            doc ^ "\n\nOptional arguments are supplied in the final Map<String,Object> parameter, which is a hash of the argument name to its value (cast to Object).  Pass an empty Map or null for no optional arguments."
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
        let doc = List.map (		(* RHBZ#501883 *)
          function
          | "" -> "<p>"
          | nonempty -> nonempty
        ) doc in
        let doc = String.concat "\n   * " doc in

        pr "  /**\n";
        pr "   * %s\n" shortdesc;
        pr "   * <p>\n";
        pr "   * %s\n" doc;
        pr "   * @throws LibGuestFSException\n";
        pr "   */\n";
      );
      pr "  ";
      generate_java_prototype ~public:true ~semicolon:false name style;
      pr "\n";
      pr "  {\n";
      pr "    if (g == 0)\n";
      pr "      throw new LibGuestFSException (\"%s: handle is closed\");\n"
        name;
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
              | OString n -> "String", "String", "", n, "\"\"" in
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
           pr "    _%s " name;
           generate_java_call_args ~handle:"g" style;
           pr ";\n"
       | RHashtable _ ->
           pr "    String[] r = _%s " name;
           generate_java_call_args ~handle:"g" style;
           pr ";\n";
           pr "\n";
           pr "    HashMap<String, String> rhash = new HashMap<String, String> ();\n";
           pr "    for (int i = 0; i < r.length; i += 2)\n";
           pr "      rhash.put (r[i], r[i+1]);\n";
           pr "    return rhash;\n"
       | _ ->
           pr "    return _%s " name;
           generate_java_call_args ~handle:"g" style;
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
          name (ret, args, []);
        pr "\n";
        pr "  {\n";
        (match ret with
        | RErr -> pr "    "
        | _ ->    pr "    return "
        );
        pr "%s (" name;
        List.iter (fun arg -> pr "%s, " (name_of_argt arg)) args;
        pr "null);\n";
        pr "  }\n";
        pr "\n"
      );

      (* Prototype for the native method. *)
      pr "  ";
      generate_java_prototype ~privat:true ~native:true name style;
      pr "\n";
      pr "\n";
  ) all_functions;

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
      | Device n | Dev_or_Path n
      | String n
      | OptString n
      | FileIn n
      | FileOut n
      | Key n ->
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
 * Libguestfs %s structure.
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

#include \"com_redhat_et_libguestfs_GuestFS.h\"
#include \"guestfs.h\"

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
Java_com_redhat_et_libguestfs_GuestFS__1create
  (JNIEnv *env, jobject obj)
{
  guestfs_h *g;

  g = guestfs_create ();
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
  guestfs_close (g);
}

";

  List.iter (
    fun (name, (ret, args, optargs as style), _, _, _, _, _) ->
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
        | Device n | Dev_or_Path n
        | String n
        | OptString n
        | FileIn n
        | FileOut n
        | Key n ->
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
        | Device n | Dev_or_Path n
        | String n
        | OptString n
        | FileIn n
        | FileOut n
        | Key n ->
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
        pr "  struct guestfs_%s_argv optargs_s;\n" name;
        pr "  const struct guestfs_%s_argv *optargs = &optargs_s;\n" name
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
                       | _ -> false) args in
      if needs_i then
        pr "  size_t i;\n";

      pr "\n";

      (* Get the parameters. *)
      List.iter (
        function
        | Pathname n
        | Device n | Dev_or_Path n
        | String n
        | FileIn n
        | FileOut n
        | Key n ->
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
            pr "  %s = guestfs_safe_malloc (g, sizeof (char *) * (%s_len+1));\n" n n;
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
        pr "  optargs_s.bitmask = joptargs_bitmask;\n";
        List.iter (
          function
          | OBool n | OInt n | OInt64 n ->
              pr "  optargs_s.%s = j%s;\n" n n
          | OString n ->
              pr "  optargs_s.%s = (*env)->GetStringUTFChars (env, j%s, NULL);\n"
                n n
        ) optargs;
      );

      pr "\n";

      (* Make the call. *)
      if optargs = [] then
        pr "  r = guestfs_%s " name
      else
        pr "  r = guestfs_%s_argv " name;
      generate_c_call_args ~handle:"g" style;
      pr ";\n";

      pr "\n";

      (* Release the parameters. *)
      List.iter (
        function
        | Pathname n
        | Device n | Dev_or_Path n
        | String n
        | FileIn n
        | FileOut n
        | Key n ->
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
  ) all_functions

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
        pr "  (*env)->SetLongField (env, jr, fl, r->%s);\n" name;
    | name, FOptPercent ->
        pr "  fl = (*env)->GetFieldID (env, cl, \"%s\", \"F\");\n" name;
        pr "  (*env)->SetFloatField (env, jr, fl, r->%s);\n" name;
    | name, FChar ->
        pr "  fl = (*env)->GetFieldID (env, cl, \"%s\", \"C\");\n" name;
        pr "  (*env)->SetLongField (env, jr, fl, r->%s);\n" name;
  ) cols;
  pr "  free (r);\n";
  pr "  return jr;\n"

and generate_java_struct_list_return typ jtyp cols =
  pr "  cl = (*env)->FindClass (env, \"com/redhat/et/libguestfs/%s\");\n" jtyp;
  pr "  jr = (*env)->NewObjectArray (env, r->len, cl, NULL);\n";
  pr "  for (i = 0; i < r->len; ++i) {\n";
  pr "    jfl = (*env)->AllocObject (env, cl);\n";
  List.iter (
    function
    | name, FString ->
        pr "    fl = (*env)->GetFieldID (env, cl, \"%s\", \"Ljava/lang/String;\");\n" name;
        pr "    (*env)->SetObjectField (env, jfl, fl, (*env)->NewStringUTF (env, r->val[i].%s));\n" name;
    | name, FUUID ->
        pr "    {\n";
        pr "      char s[33];\n";
        pr "      memcpy (s, r->val[i].%s, 32);\n" name;
        pr "      s[32] = 0;\n";
        pr "      fl = (*env)->GetFieldID (env, cl, \"%s\", \"Ljava/lang/String;\");\n" name;
        pr "      (*env)->SetObjectField (env, jfl, fl, (*env)->NewStringUTF (env, s));\n";
        pr "    }\n";
    | name, FBuffer ->
        pr "    {\n";
        pr "      size_t len = r->val[i].%s_len;\n" name;
        pr "      char s[len+1];\n";
        pr "      memcpy (s, r->val[i].%s, len);\n" name;
        pr "      s[len] = 0;\n";
        pr "      fl = (*env)->GetFieldID (env, cl, \"%s\", \"Ljava/lang/String;\");\n" name;
        pr "      (*env)->SetObjectField (env, jfl, fl, (*env)->NewStringUTF (env, s));\n";
        pr "    }\n";
    | name, (FBytes|FUInt64|FInt64) ->
        pr "    fl = (*env)->GetFieldID (env, cl, \"%s\", \"J\");\n" name;
        pr "    (*env)->SetLongField (env, jfl, fl, r->val[i].%s);\n" name;
    | name, (FUInt32|FInt32) ->
        pr "    fl = (*env)->GetFieldID (env, cl, \"%s\", \"I\");\n" name;
        pr "    (*env)->SetLongField (env, jfl, fl, r->val[i].%s);\n" name;
    | name, FOptPercent ->
        pr "    fl = (*env)->GetFieldID (env, cl, \"%s\", \"F\");\n" name;
        pr "    (*env)->SetFloatField (env, jfl, fl, r->val[i].%s);\n" name;
    | name, FChar ->
        pr "    fl = (*env)->GetFieldID (env, cl, \"%s\", \"C\");\n" name;
        pr "    (*env)->SetLongField (env, jfl, fl, r->val[i].%s);\n" name;
  ) cols;
  pr "    (*env)->SetObjectArrayElement (env, jfl, i, jfl);\n";
  pr "  }\n";
  pr "  guestfs_free_%s_list (r);\n" typ;
  pr "  return jr;\n"

and generate_java_makefile_inc () =
  generate_header HashStyle GPLv2plus;

  pr "java_built_sources = \\\n";
  List.iter (
    fun (typ, jtyp) ->
        pr "\tcom/redhat/et/libguestfs/%s.java \\\n" jtyp;
  ) camel_structs;
  pr "\tcom/redhat/et/libguestfs/GuestFS.java\n"

and generate_java_gitignore () =
  List.iter (fun (_, jtyp) -> pr "%s.java\n" jtyp) camel_structs
