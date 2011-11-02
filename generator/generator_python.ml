(* libguestfs
 * Copyright (C) 2009-2011 Red Hat Inc.
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

(* Generate Python C module. *)
let rec generate_python_c () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

#include \"guestfs-py.h\"

/* This list should be freed (but not the strings) after use. */
static char **
get_string_list (PyObject *obj)
{
  size_t i, len;
  char **r;
#ifndef HAVE_PYSTRING_ASSTRING
  PyObject *bytes;
#endif

  assert (obj);

  if (!PyList_Check (obj)) {
    PyErr_SetString (PyExc_RuntimeError, \"expecting a list parameter\");
    return NULL;
  }

  Py_ssize_t slen = PyList_Size (obj);
  if (slen == -1) {
    PyErr_SetString (PyExc_RuntimeError, \"get_string_list: PyList_Size failure\");
    return NULL;
  }
  len = (size_t) slen;
  r = malloc (sizeof (char *) * (len+1));
  if (r == NULL) {
    PyErr_SetString (PyExc_RuntimeError, \"get_string_list: out of memory\");
    return NULL;
  }

  for (i = 0; i < len; ++i) {
#ifdef HAVE_PYSTRING_ASSTRING
    r[i] = PyString_AsString (PyList_GetItem (obj, i));
#else
    bytes = PyUnicode_AsUTF8String (PyList_GetItem (obj, i));
    r[i] = PyBytes_AS_STRING (bytes);
#endif
  }
  r[len] = NULL;

  return r;
}

static PyObject *
put_string_list (char * const * const argv)
{
  PyObject *list;
  int argc, i;

  for (argc = 0; argv[argc] != NULL; ++argc)
    ;

  list = PyList_New (argc);
  for (i = 0; i < argc; ++i) {
#ifdef HAVE_PYSTRING_ASSTRING
    PyList_SetItem (list, i, PyString_FromString (argv[i]));
#else
    PyList_SetItem (list, i, PyUnicode_FromString (argv[i]));
#endif
  }

  return list;
}

static PyObject *
put_table (char * const * const argv)
{
  PyObject *list, *item;
  int argc, i;

  for (argc = 0; argv[argc] != NULL; ++argc)
    ;

  list = PyList_New (argc >> 1);
  for (i = 0; i < argc; i += 2) {
    item = PyTuple_New (2);
#ifdef HAVE_PYSTRING_ASSTRING
    PyTuple_SetItem (item, 0, PyString_FromString (argv[i]));
    PyTuple_SetItem (item, 1, PyString_FromString (argv[i+1]));
#else
    PyTuple_SetItem (item, 0, PyUnicode_FromString (argv[i]));
    PyTuple_SetItem (item, 1, PyUnicode_FromString (argv[i+1]));
#endif
    PyList_SetItem (list, i >> 1, item);
  }

  return list;
}

static void
free_strings (char **argv)
{
  int argc;

  for (argc = 0; argv[argc] != NULL; ++argc)
    free (argv[argc]);
  free (argv);
}

";

  let emit_put_list_function typ =
    pr "static PyObject *\n";
    pr "put_%s_list (struct guestfs_%s_list *%ss)\n" typ typ typ;
    pr "{\n";
    pr "  PyObject *list;\n";
    pr "  size_t i;\n";
    pr "\n";
    pr "  list = PyList_New (%ss->len);\n" typ;
    pr "  for (i = 0; i < %ss->len; ++i)\n" typ;
    pr "    PyList_SetItem (list, i, put_%s (&%ss->val[i]));\n" typ typ;
    pr "  return list;\n";
    pr "};\n";
    pr "\n"
  in

  (* Structures, turned into Python dictionaries. *)
  List.iter (
    fun (typ, cols) ->
      pr "static PyObject *\n";
      pr "put_%s (struct guestfs_%s *%s)\n" typ typ typ;
      pr "{\n";
      pr "  PyObject *dict;\n";
      pr "\n";
      pr "  dict = PyDict_New ();\n";
      List.iter (
        function
        | name, FString ->
            pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
            pr "#ifdef HAVE_PYSTRING_ASSTRING\n";
            pr "                        PyString_FromString (%s->%s));\n"
              typ name;
            pr "#else\n";
            pr "                        PyUnicode_FromString (%s->%s));\n"
              typ name;
            pr "#endif\n"
        | name, FBuffer ->
            pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
            pr "#ifdef HAVE_PYSTRING_ASSTRING\n";
            pr "                        PyString_FromStringAndSize (%s->%s, %s->%s_len));\n"
              typ name typ name;
            pr "#else\n";
            pr "                        PyBytes_FromStringAndSize (%s->%s, %s->%s_len));\n"
              typ name typ name;
            pr "#endif\n"
        | name, FUUID ->
            pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
            pr "#ifdef HAVE_PYSTRING_ASSTRING\n";
            pr "                        PyString_FromStringAndSize (%s->%s, 32));\n"
              typ name;
            pr "#else\n";
            pr "                        PyBytes_FromStringAndSize (%s->%s, 32));\n"
              typ name;
            pr "#endif\n"
        | name, (FBytes|FUInt64) ->
            pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
            pr "                        PyLong_FromUnsignedLongLong (%s->%s));\n"
              typ name
        | name, FInt64 ->
            pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
            pr "                        PyLong_FromLongLong (%s->%s));\n"
              typ name
        | name, FUInt32 ->
            pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
            pr "                        PyLong_FromUnsignedLong (%s->%s));\n"
              typ name
        | name, FInt32 ->
            pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
            pr "                        PyLong_FromLong (%s->%s));\n"
              typ name
        | name, FOptPercent ->
            pr "  if (%s->%s >= 0)\n" typ name;
            pr "    PyDict_SetItemString (dict, \"%s\",\n" name;
            pr "                          PyFloat_FromDouble ((double) %s->%s));\n"
              typ name;
            pr "  else {\n";
            pr "    Py_INCREF (Py_None);\n";
            pr "    PyDict_SetItemString (dict, \"%s\", Py_None);\n" name;
            pr "  }\n"
        | name, FChar ->
            pr "#ifdef HAVE_PYSTRING_ASSTRING\n";
            pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
            pr "                        PyString_FromStringAndSize (&dirent->%s, 1));\n" name;
            pr "#else\n";
            pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
            pr "                        PyUnicode_FromStringAndSize (&dirent->%s, 1));\n" name;
            pr "#endif\n"
      ) cols;
      pr "  return dict;\n";
      pr "};\n";
      pr "\n";

  ) structs;

  (* Emit a put_TYPE_list function definition only if that function is used. *)
  List.iter (
    function
    | typ, (RStructListOnly | RStructAndList) ->
        (* generate the function for typ *)
        emit_put_list_function typ
    | typ, _ -> () (* empty *)
  ) (rstructs_used_by all_functions);

  (* Python wrapper functions. *)
  List.iter (
    fun (name, (ret, args, optargs as style), _, _, _, _, _) ->
      pr "static PyObject *\n";
      pr "py_guestfs_%s (PyObject *self, PyObject *args)\n" name;
      pr "{\n";

      pr "  PyThreadState *py_save = NULL;\n";
      pr "  PyObject *py_g;\n";
      pr "  guestfs_h *g;\n";
      pr "  PyObject *py_r;\n";

      if optargs <> [] then (
        pr "  struct guestfs_%s_argv optargs_s;\n" name;
        pr "  struct guestfs_%s_argv *optargs = &optargs_s;\n" name;
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

      List.iter (
        function
        | Pathname n | Device n | Dev_or_Path n | String n | Key n
        | FileIn n | FileOut n ->
            pr "  const char *%s;\n" n
        | OptString n -> pr "  const char *%s;\n" n
        | BufferIn n ->
            pr "  const char *%s;\n" n;
            pr "  Py_ssize_t %s_size;\n" n
        | StringList n | DeviceList n ->
            pr "  PyObject *py_%s;\n" n;
            pr "  char **%s;\n" n
        | Bool n -> pr "  int %s;\n" n
        | Int n -> pr "  int %s;\n" n
        | Int64 n -> pr "  long long %s;\n" n
        | Pointer (t, n) ->
            pr "  long long %s_int64;\n" n;
            pr "  %s %s;\n" t n
      ) args;

      if optargs <> [] then (
        (* XXX This is horrible.  We have to use sentinel values on the
         * Python side to denote values not set.
         *)
        (* Since we don't know if Python types will exactly match
         * structure types, declare some local variables here.
         *)
        List.iter (
          function
          | Bool n
          | Int n -> pr "  int optargs_t_%s = -1;\n" n
          | Int64 n -> pr "  long long optargs_t_%s = -1;\n" n
          | String n -> pr "  const char *optargs_t_%s = NULL;\n" n
          | _ -> assert false
        ) optargs
      );

      pr "\n";

      if optargs <> [] then (
        pr "  optargs_s.bitmask = 0;\n";
        pr "\n"
      );

      (* Convert the required parameters. *)
      pr "  if (!PyArg_ParseTuple (args, (char *) \"O";
      List.iter (
        function
        | Pathname _ | Device _ | Dev_or_Path _ | String _ | Key _
        | FileIn _ | FileOut _ -> pr "s"
        | OptString _ -> pr "z"
        | StringList _ | DeviceList _ -> pr "O"
        | Bool _ -> pr "i" (* XXX Python has booleans? *)
        | Int _ -> pr "i"
        | Int64 _ | Pointer _ ->
            (* XXX Whoever thought it was a good idea to
             * emulate C's int/long/long long in Python?
             *)
            pr "L"
        | BufferIn _ -> pr "s#"
      ) args;

      (* Optional parameters. *)
      if optargs <> [] then (
        List.iter (
          function
          | Bool _ | Int _ -> pr "i"
          | Int64 _ -> pr "L"
          | String _ -> pr "z" (* because we use None to mean not set *)
          | _ -> assert false
        ) optargs;
      );

      pr ":guestfs_%s\",\n" name;
      pr "                         &py_g";
      List.iter (
        function
        | Pathname n | Device n | Dev_or_Path n | String n | Key n
        | FileIn n | FileOut n -> pr ", &%s" n
        | OptString n -> pr ", &%s" n
        | StringList n | DeviceList n -> pr ", &py_%s" n
        | Bool n -> pr ", &%s" n
        | Int n -> pr ", &%s" n
        | Int64 n -> pr ", &%s" n
        | Pointer (_, n) -> pr ", &%s_int64" n
        | BufferIn n -> pr ", &%s, &%s_size" n n
      ) args;

      List.iter (
        function
        | Bool n | Int n | Int64 n | String n -> pr ", &optargs_t_%s" n
        | _ -> assert false
      ) optargs;

      pr "))\n";
      pr "    return NULL;\n";

      pr "  g = get_handle (py_g);\n";
      List.iter (
        function
        | Pathname _ | Device _ | Dev_or_Path _ | String _ | Key _
        | FileIn _ | FileOut _ | OptString _ | Bool _ | Int _ | Int64 _
        | BufferIn _ -> ()
        | StringList n | DeviceList n ->
            pr "  %s = get_string_list (py_%s);\n" n n;
            pr "  if (!%s) return NULL;\n" n
        | Pointer (t, n) ->
            pr "  %s = (%s) (intptr_t) %s_int64;\n" n t n
      ) args;

      pr "\n";

      if optargs <> [] then (
        let uc_name = String.uppercase name in
        List.iter (
          fun argt ->
            let n = name_of_argt argt in
            let uc_n = String.uppercase n in
            pr "  if (optargs_t_%s != " n;
            (match argt with
             | Bool _ | Int _ | Int64 _ -> pr "-1"
             | String _ -> pr "NULL"
             | _ -> assert false
            );
            pr ") {\n";
            pr "    optargs_s.%s = optargs_t_%s;\n" n n;
            pr "    optargs_s.bitmask |= GUESTFS_%s_%s_BITMASK;\n" uc_name uc_n;
            pr "  }\n"
        ) optargs;
        pr "\n"
      );

      (* Release Python GIL while running.  This code is from
       * libvirt/python/typewrappers.h.  Thanks to Dan Berrange for
       * showing us how to do this properly.
       *)
      pr "  if (PyEval_ThreadsInitialized ())\n";
      pr "    py_save = PyEval_SaveThread ();\n";
      pr "\n";

      if optargs = [] then
        pr "  r = guestfs_%s " name
      else
        pr "  r = guestfs_%s_argv " name;
      generate_c_call_args ~handle:"g" style;
      pr ";\n";

      pr "\n";
      pr "  if (PyEval_ThreadsInitialized ())\n";
      pr "    PyEval_RestoreThread (py_save);\n";
      pr "\n";

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
           pr "  if (r == -1) {\n";
           pr "    PyErr_SetString (PyExc_RuntimeError, guestfs_last_error (g));\n";
           pr "    return NULL;\n";
           pr "  }\n"
       | `ErrorIsNULL ->
           pr "  if (r == NULL) {\n";
           pr "    PyErr_SetString (PyExc_RuntimeError, guestfs_last_error (g));\n";
           pr "    return NULL;\n";
           pr "  }\n"
      );
      pr "\n";

      (match ret with
       | RErr ->
           pr "  Py_INCREF (Py_None);\n";
           pr "  py_r = Py_None;\n"
       | RInt _
       | RBool _ -> pr "  py_r = PyLong_FromLong ((long) r);\n"
       | RInt64 _ -> pr "  py_r = PyLong_FromLongLong (r);\n"
       | RConstString _ ->
           pr "#ifdef HAVE_PYSTRING_ASSTRING\n";
           pr "  py_r = PyString_FromString (r);\n";
           pr "#else\n";
           pr "  py_r = PyUnicode_FromString (r);\n";
           pr "#endif\n"
       | RConstOptString _ ->
           pr "  if (r) {\n";
           pr "#ifdef HAVE_PYSTRING_ASSTRING\n";
           pr "    py_r = PyString_FromString (r);\n";
           pr "#else\n";
           pr "    py_r = PyUnicode_FromString (r);\n";
           pr "#endif\n";
           pr "  } else {\n";
           pr "    Py_INCREF (Py_None);\n";
           pr "    py_r = Py_None;\n";
           pr "  }\n"
       | RString _ ->
           pr "#ifdef HAVE_PYSTRING_ASSTRING\n";
           pr "  py_r = PyString_FromString (r);\n";
           pr "#else\n";
           pr "  py_r = PyUnicode_FromString (r);\n";
           pr "#endif\n";
           pr "  free (r);\n"
       | RStringList _ ->
           pr "  py_r = put_string_list (r);\n";
           pr "  free_strings (r);\n"
       | RStruct (_, typ) ->
           pr "  py_r = put_%s (r);\n" typ;
           pr "  guestfs_free_%s (r);\n" typ
       | RStructList (_, typ) ->
           pr "  py_r = put_%s_list (r);\n" typ;
           pr "  guestfs_free_%s_list (r);\n" typ
       | RHashtable n ->
           pr "  py_r = put_table (r);\n";
           pr "  free_strings (r);\n"
       | RBufferOut _ ->
           pr "#ifdef HAVE_PYSTRING_ASSTRING\n";
           pr "  py_r = PyString_FromStringAndSize (r, size);\n";
           pr "#else\n";
           pr "  py_r = PyBytes_FromStringAndSize (r, size);\n";
           pr "#endif\n";
           pr "  free (r);\n"
      );

      pr "  return py_r;\n";
      pr "}\n";
      pr "\n"
  ) all_functions;

  (* Table of functions. *)
  pr "static PyMethodDef methods[] = {\n";
  pr "  { (char *) \"create\", py_guestfs_create, METH_VARARGS, NULL },\n";
  pr "  { (char *) \"close\", py_guestfs_close, METH_VARARGS, NULL },\n";
  pr "  { (char *) \"set_event_callback\",\n";
  pr "    py_guestfs_set_event_callback, METH_VARARGS, NULL },\n";
  pr "  { (char *) \"delete_event_callback\",\n";
  pr "    py_guestfs_delete_event_callback, METH_VARARGS, NULL },\n";
  List.iter (
    fun (name, _, _, _, _, _, _) ->
      pr "  { (char *) \"%s\", py_guestfs_%s, METH_VARARGS, NULL },\n"
        name name
  ) all_functions;
  pr "  { NULL, NULL, 0, NULL }\n";
  pr "};\n";
  pr "\n";

  (* Init function. *)
  pr "\
#if PY_MAJOR_VERSION >= 3
static struct PyModuleDef moduledef = {
  PyModuleDef_HEAD_INIT,
  \"libguestfsmod\",     /* m_name */
  \"libguestfs module\",   /* m_doc */
  -1,                    /* m_size */
  methods,               /* m_methods */
  NULL,                  /* m_reload */
  NULL,                  /* m_traverse */
  NULL,                  /* m_clear */
  NULL,                  /* m_free */
};
#endif

static PyObject *
moduleinit (void)
{
  PyObject *m;

#if PY_MAJOR_VERSION >= 3
  m = PyModule_Create (&moduledef);
#else
  m = Py_InitModule ((char *) \"libguestfsmod\", methods);
#endif

  return m; /* m might be NULL if module init failed */
}

#if PY_MAJOR_VERSION >= 3
PyMODINIT_FUNC
PyInit_libguestfsmod (void)
{
  return moduleinit ();
}
#else
void
initlibguestfsmod (void)
{
  (void) moduleinit ();
}
#endif
"

(* Generate Python module. *)
and generate_python_py () =
  generate_header HashStyle LGPLv2plus;

  pr "\
\"\"\"Python bindings for libguestfs

import guestfs
g = guestfs.GuestFS ()
g.add_drive_opts (\"guest.img\", format=\"raw\")
g.launch ()
parts = g.list_partitions ()

The guestfs module provides a Python binding to the libguestfs API
for examining and modifying virtual machine disk images.

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

Errors which happen while using the API are turned into Python
RuntimeError exceptions.

To create a guestfs handle you usually have to perform the following
sequence of calls:

# Create the handle, call add_drive* at least once, and possibly
# several times if the guest has multiple block devices:
g = guestfs.GuestFS ()
g.add_drive_opts (\"guest.img\", format=\"raw\")

# Launch the qemu subprocess and wait for it to become ready:
g.launch ()

# Now you can issue commands, for example:
logvols = g.lvs ()

\"\"\"

import libguestfsmod

";

  List.iter (
    fun (name, bitmask) ->
      pr "EVENT_%s = 0x%x\n" (String.uppercase name) bitmask
  ) events;
  pr "\n";

  pr "\
class ClosedHandle(ValueError):
    pass

class GuestFS:
    \"\"\"Instances of this class are libguestfs API handles.\"\"\"

    def __init__ (self):
        \"\"\"Create a new libguestfs handle.\"\"\"
        self._o = libguestfsmod.create ()

    def __del__ (self):
        if self._o:
            libguestfsmod.close (self._o)

    def _check_not_closed (self):
        if not self._o:
            raise ClosedHandle (\"GuestFS: method called on closed handle\")

    def close (self):
        \"\"\"Explicitly close the guestfs handle.

        The handle is closed implicitly when its reference count goes
        to zero (eg. when it goes out of scope or the program ends).

        This call is only needed if you want to force the handle to
        close now.  After calling this, the program must not call
        any method on the handle (except the implicit call to
        __del__ which happens when the final reference is cleaned up).
        \"\"\"
        self._check_not_closed ()
        libguestfsmod.close (self._o)
        self._o = None

    def set_event_callback (self, cb, event_bitmask):
        \"\"\"Register an event callback.

        Register \"cb\" as a callback function for all of the
        events in \"event_bitmask\".  \"event_bitmask\" should be
        one or more \"guestfs.EVENT_*\" flags logically or'd together.

        This function returns an event handle which can be used
        to delete the callback (see \"delete_event_callback\").

        The callback function receives 4 parameters:

        cb (event, event_handle, buf, array)

        \"event\" is one of the \"EVENT_*\" flags.  \"buf\" is a
        message buffer (only for some types of events).  \"array\"
        is an array of integers (only for some types of events).

        You should read the documentation for
        \"guestfs_set_event_callback\" in guestfs(3) before using
        this function.
        \"\"\"
        self._check_not_closed ()
        return libguestfsmod.set_event_callback (self._o, cb, event_bitmask)

    def delete_event_callback (self, event_handle):
        \"\"\"Delete an event callback.\"\"\"
        self._check_not_closed ()
        libguestfsmod.delete_event_callback (self._o, event_handle)

";

  List.iter (
    fun (name, (ret, args, optargs), _, flags, _, _, longdesc) ->
      pr "    def %s (self" name;
      List.iter (fun arg -> pr ", %s" (name_of_argt arg)) args;
      List.iter (
        function
        | Bool n | Int n | Int64 n -> pr ", %s=-1" n
        | String n -> pr ", %s=None" n
        | _ -> assert false
      ) optargs;
      pr "):\n";

      if not (List.mem NotInDocs flags) then (
        let doc = replace_str longdesc "C<guestfs_" "C<g." in
        let doc =
          match ret with
          | RErr | RInt _ | RInt64 _ | RBool _
          | RConstOptString _ | RConstString _
          | RString _ | RBufferOut _ -> doc
          | RStringList _ ->
              doc ^ "\n\nThis function returns a list of strings."
          | RStruct (_, typ) ->
              doc ^ sprintf "\n\nThis function returns a dictionary, with keys matching the various fields in the guestfs_%s structure." typ
          | RStructList (_, typ) ->
              doc ^ sprintf "\n\nThis function returns a list of %ss.  Each %s is represented as a dictionary." typ typ
          | RHashtable _ ->
              doc ^ "\n\nThis function returns a dictionary." in
        let doc =
          if List.mem ProtocolLimitWarning flags then
            doc ^ "\n\n" ^ protocol_limit_warning
          else doc in
        let doc =
          match deprecation_notice flags with
          | None -> doc
          | Some txt -> doc ^ "\n\n" ^ txt in
        let doc = pod2text ~width:60 name doc in
        let doc = List.map (fun line -> replace_str line "\\" "\\\\") doc in
        let doc = String.concat "\n        " doc in
        pr "        \"\"\"%s\"\"\"\n" doc;
      );
      (* Callers might pass in iterables instead of plain lists;
       * convert those to plain lists because the C side of things
       * cannot deal with iterables.  (RHBZ#693306).
       *)
      List.iter (
        function
        | Pathname _ | Device _ | Dev_or_Path _ | String _ | Key _
        | FileIn _ | FileOut _ | OptString _ | Bool _ | Int _ | Int64 _
        | BufferIn _ | Pointer _ -> ()
        | StringList n | DeviceList n ->
            pr "        %s = list (%s)\n" n n
      ) args;
      pr "        self._check_not_closed ()\n";
      pr "        return libguestfsmod.%s (self._o" name;
      List.iter (fun arg -> pr ", %s" (name_of_argt arg)) (args@optargs);
      pr ")\n\n";
  ) all_functions
