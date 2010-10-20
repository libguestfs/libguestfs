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

(* Generate Python C module. *)
let rec generate_python_c () =
  generate_header CStyle LGPLv2plus;

  pr "\
#define PY_SSIZE_T_CLEAN 1
#include <Python.h>

#if PY_VERSION_HEX < 0x02050000
typedef int Py_ssize_t;
#define PY_SSIZE_T_MAX INT_MAX
#define PY_SSIZE_T_MIN INT_MIN
#endif

#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

#include \"guestfs.h\"

#ifndef HAVE_PYCAPSULE_NEW
typedef struct {
  PyObject_HEAD
  guestfs_h *g;
} Pyguestfs_Object;
#endif

static guestfs_h *
get_handle (PyObject *obj)
{
  assert (obj);
  assert (obj != Py_None);
#ifndef HAVE_PYCAPSULE_NEW
  return ((Pyguestfs_Object *) obj)->g;
#else
  return (guestfs_h*) PyCapsule_GetPointer(obj, \"guestfs_h\");
#endif
}

static PyObject *
put_handle (guestfs_h *g)
{
  assert (g);
#ifndef HAVE_PYCAPSULE_NEW
  return
    PyCObject_FromVoidPtrAndDesc ((void *) g, (char *) \"guestfs_h\", NULL);
#else
  return PyCapsule_New ((void *) g, \"guestfs_h\", NULL);
#endif
}

/* This list should be freed (but not the strings) after use. */
static char **
get_string_list (PyObject *obj)
{
  size_t i, len;
  char **r;

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

  for (i = 0; i < len; ++i)
    r[i] = PyString_AsString (PyList_GetItem (obj, i));
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
  for (i = 0; i < argc; ++i)
    PyList_SetItem (list, i, PyString_FromString (argv[i]));

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
    PyTuple_SetItem (item, 0, PyString_FromString (argv[i]));
    PyTuple_SetItem (item, 1, PyString_FromString (argv[i+1]));
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

static PyObject *
py_guestfs_create (PyObject *self, PyObject *args)
{
  guestfs_h *g;

  g = guestfs_create ();
  if (g == NULL) {
    PyErr_SetString (PyExc_RuntimeError,
                     \"guestfs.create: failed to allocate handle\");
    return NULL;
  }
  guestfs_set_error_handler (g, NULL, NULL);
  /* This can return NULL, but in that case put_handle will have
   * set the Python error string.
   */
  return put_handle (g);
}

static PyObject *
py_guestfs_close (PyObject *self, PyObject *args)
{
  PyObject *py_g;
  guestfs_h *g;

  if (!PyArg_ParseTuple (args, (char *) \"O:guestfs_close\", &py_g))
    return NULL;
  g = get_handle (py_g);

  guestfs_close (g);

  Py_INCREF (Py_None);
  return Py_None;
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
            pr "                        PyString_FromString (%s->%s));\n"
              typ name
        | name, FBuffer ->
            pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
            pr "                        PyString_FromStringAndSize (%s->%s, %s->%s_len));\n"
              typ name typ name
        | name, FUUID ->
            pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
            pr "                        PyString_FromStringAndSize (%s->%s, 32));\n"
              typ name
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
            pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
            pr "                        PyString_FromStringAndSize (&dirent->%s, 1));\n" name
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

      pr "  PyObject *py_g;\n";
      pr "  guestfs_h *g;\n";
      pr "  PyObject *py_r;\n";

      if optargs <> [] then (
        pr "  struct guestfs_%s_argv optargs_s;\n" name;
        pr "  struct guestfs_%s_argv *optargs = &optargs_s;\n" name;
      );

      let error_code =
        match ret with
        | RErr | RInt _ | RBool _ -> pr "  int r;\n"; "-1"
        | RInt64 _ -> pr "  int64_t r;\n"; "-1"
        | RConstString _ | RConstOptString _ ->
            pr "  const char *r;\n"; "NULL"
        | RString _ -> pr "  char *r;\n"; "NULL"
        | RStringList _ | RHashtable _ -> pr "  char **r;\n"; "NULL"
        | RStruct (_, typ) -> pr "  struct guestfs_%s *r;\n" typ; "NULL"
        | RStructList (_, typ) ->
            pr "  struct guestfs_%s_list *r;\n" typ; "NULL"
        | RBufferOut _ ->
            pr "  char *r;\n";
            pr "  size_t size;\n";
            "NULL" in

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
        | Int64 _ -> pr "L" (* XXX Whoever thought it was a good idea to
                             * emulate C's int/long/long long in Python?
                             *)
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
        | BufferIn _ -> ()
        | StringList n | DeviceList n ->
            pr "  free (%s);\n" n
      ) args;

      pr "  if (r == %s) {\n" error_code;
      pr "    PyErr_SetString (PyExc_RuntimeError, guestfs_last_error (g));\n";
      pr "    return NULL;\n";
      pr "  }\n";
      pr "\n";

      (match ret with
       | RErr ->
           pr "  Py_INCREF (Py_None);\n";
           pr "  py_r = Py_None;\n"
       | RInt _
       | RBool _ -> pr "  py_r = PyInt_FromLong ((long) r);\n"
       | RInt64 _ -> pr "  py_r = PyLong_FromLongLong (r);\n"
       | RConstString _ -> pr "  py_r = PyString_FromString (r);\n"
       | RConstOptString _ ->
           pr "  if (r)\n";
           pr "    py_r = PyString_FromString (r);\n";
           pr "  else {\n";
           pr "    Py_INCREF (Py_None);\n";
           pr "    py_r = Py_None;\n";
           pr "  }\n"
       | RString _ ->
           pr "  py_r = PyString_FromString (r);\n";
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
           pr "  py_r = PyString_FromStringAndSize (r, size);\n";
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
void
initlibguestfsmod (void)
{
  static int initialized = 0;

  if (initialized) return;
  Py_InitModule ((char *) \"libguestfsmod\", methods);
  initialized = 1;
}
"

(* Generate Python module. *)
and generate_python_py () =
  generate_header HashStyle LGPLv2plus;

  pr "\
u\"\"\"Python bindings for libguestfs

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

class GuestFS:
    \"\"\"Instances of this class are libguestfs API handles.\"\"\"

    def __init__ (self):
        \"\"\"Create a new libguestfs handle.\"\"\"
        self._o = libguestfsmod.create ()

    def __del__ (self):
        libguestfsmod.close (self._o)

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
          if List.mem DangerWillRobinson flags then
            doc ^ "\n\n" ^ danger_will_robinson
          else doc in
        let doc =
          match deprecation_notice flags with
          | None -> doc
          | Some txt -> doc ^ "\n\n" ^ txt in
        let doc = pod2text ~width:60 name doc in
        let doc = List.map (fun line -> replace_str line "\\" "\\\\") doc in
        let doc = String.concat "\n        " doc in
        pr "        u\"\"\"%s\"\"\"\n" doc;
      );
      pr "        return libguestfsmod.%s (self._o" name;
      List.iter (fun arg -> pr ", %s" (name_of_argt arg)) (args@optargs);
      pr ")\n\n";
  ) all_functions
