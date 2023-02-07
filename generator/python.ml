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
open C
open Events

let generate_header = generate_header ~inputs:["generator/python.ml"]

(* Generate Python C actions. *)
let rec generate_python_actions_h () =
  generate_header CStyle LGPLv2plus;

  pr "\
#ifndef GUESTFS_PYTHON_ACTIONS_H_
#define GUESTFS_PYTHON_ACTIONS_H_

#include \"guestfs.h\"
#include \"guestfs-stringlists-utils.h\"

#define PY_SSIZE_T_CLEAN 1

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored \"-Wcast-align\"
#include <Python.h>
#pragma GCC diagnostic pop

static inline guestfs_h *
get_handle (PyObject *obj)
{
  assert (obj);
  assert (obj != Py_None);
  return (guestfs_h*) PyCapsule_GetPointer(obj, \"guestfs_h\");
}

static inline PyObject *
put_handle (guestfs_h *g)
{
  assert (g);
  return PyCapsule_New ((void *) g, \"guestfs_h\", NULL);
}

extern void guestfs_int_py_extend_module (PyObject *module);

extern PyObject *guestfs_int_py_create (PyObject *self, PyObject *args);
extern PyObject *guestfs_int_py_close (PyObject *self, PyObject *args);
extern PyObject *guestfs_int_py_set_event_callback (PyObject *self, PyObject *args);
extern PyObject *guestfs_int_py_delete_event_callback (PyObject *self, PyObject *args);
extern PyObject *guestfs_int_py_event_to_string (PyObject *self, PyObject *args);
extern char **guestfs_int_py_get_string_list (PyObject *obj);
extern PyObject *guestfs_int_py_put_string_list (char * const * const argv);
extern PyObject *guestfs_int_py_put_table (char * const * const argv);
extern PyObject *guestfs_int_py_fromstring (const char *str);
extern PyObject *guestfs_int_py_fromstringsize (const char *str, size_t size);
extern char *guestfs_int_py_asstring (PyObject *obj);

";

  let emit_put_list_decl typ =
    pr "#ifdef GUESTFS_HAVE_STRUCT_%s\n" (String.uppercase_ascii typ);
    pr "extern PyObject *guestfs_int_py_put_%s_list (struct guestfs_%s_list *%ss);\n" typ typ typ;
    pr "#endif\n";
  in

  List.iter (
    fun { s_name = typ } ->
      pr "#ifdef GUESTFS_HAVE_STRUCT_%s\n" (String.uppercase_ascii typ);
      pr "extern PyObject *guestfs_int_py_put_%s (struct guestfs_%s *%s);\n" typ typ typ;
      pr "#endif\n";
  ) external_structs;

  List.iter (
    function
    | typ, (RStructListOnly | RStructAndList) ->
        (* generate the function for typ *)
        emit_put_list_decl typ
    | typ, _ -> () (* empty *)
  ) (rstructs_used_by (actions |> external_functions));

  pr "\n";

  List.iter (
    fun { name; c_name } ->
      pr "#ifdef GUESTFS_HAVE_%s\n" (String.uppercase_ascii c_name);
      pr "extern PyObject *guestfs_int_py_%s (PyObject *self, PyObject *args);\n" name;
      pr "#endif\n"
  ) (actions |> external_functions |> sort);

  pr "\n";
  pr "#endif /* GUESTFS_PYTHON_ACTIONS_H_ */\n"

and generate_python_structs () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

#include \"actions.h\"

";

  let emit_put_list_function typ =
    pr "#ifdef GUESTFS_HAVE_STRUCT_%s\n" (String.uppercase_ascii typ);
    pr "PyObject *\n";
    pr "guestfs_int_py_put_%s_list (struct guestfs_%s_list *%ss)\n" typ typ typ;
    pr "{\n";
    pr "  PyObject *list, *element;\n";
    pr "  size_t i;\n";
    pr "\n";
    pr "  list = PyList_New (%ss->len);\n" typ;
    pr "  if (list == NULL)\n";
    pr "    return NULL;\n";
    pr "  for (i = 0; i < %ss->len; ++i) {\n" typ;
    pr "    element = guestfs_int_py_put_%s (&%ss->val[i]);\n" typ typ;
    pr "    if (element == NULL) {\n";
    pr "      Py_CLEAR (list);\n";
    pr "      return NULL;\n";
    pr "    }\n";
    pr "    PyList_SetItem (list, i, element);\n";
    pr "  }\n";
    pr "  return list;\n";
    pr "};\n";
    pr "#endif\n";
    pr "\n"
  in

  (* Structures, turned into Python dictionaries. *)
  List.iter (
    fun { s_name = typ; s_cols = cols } ->
      pr "#ifdef GUESTFS_HAVE_STRUCT_%s\n" (String.uppercase_ascii typ);
      pr "PyObject *\n";
      pr "guestfs_int_py_put_%s (struct guestfs_%s *%s)\n" typ typ typ;
      pr "{\n";
      pr "  PyObject *dict, *value;\n";
      pr "\n";
      pr "  dict = PyDict_New ();\n";
      pr "  if (dict == NULL)\n";
      pr "    return NULL;\n";
      List.iter (
        function
        | name, FString ->
            pr "  value = guestfs_int_py_fromstring (%s->%s);\n" typ name;
            pr "  if (value == NULL)\n";
            pr "    goto err;\n";
            pr "  PyDict_SetItemString (dict, \"%s\", value);\n" name;
            pr "  Py_DECREF (value);\n"
        | name, FBuffer ->
            pr "  value = PyBytes_FromStringAndSize (%s->%s, %s->%s_len);\n"
              typ name typ name;
            pr "  if (value == NULL)\n";
            pr "    goto err;\n";
            pr "  PyDict_SetItemString (dict, \"%s\", value);\n" name;
            pr "  Py_DECREF (value);\n"
        | name, FUUID ->
            pr "  value = guestfs_int_py_fromstringsize (%s->%s, 32);\n"
              typ name;
            pr "  if (value == NULL)\n";
            pr "    goto err;\n";
            pr "  PyDict_SetItemString (dict, \"%s\", value);\n" name;
            pr "  Py_DECREF (value);\n"
        | name, (FBytes|FUInt64) ->
            pr "  value = PyLong_FromUnsignedLongLong (%s->%s);\n" typ name;
            pr "  if (value == NULL)\n";
            pr "    goto err;\n";
            pr "  PyDict_SetItemString (dict, \"%s\", value);\n" name;
            pr "  Py_DECREF (value);\n"
        | name, FInt64 ->
            pr "  value = PyLong_FromLongLong (%s->%s);\n" typ name;
            pr "  if (value == NULL)\n";
            pr "    goto err;\n";
            pr "  PyDict_SetItemString (dict, \"%s\", value);\n" name;
            pr "  Py_DECREF (value);\n"
        | name, FUInt32 ->
            pr "  value = PyLong_FromUnsignedLong (%s->%s);\n" typ name;
            pr "  if (value == NULL)\n";
            pr "    goto err;\n";
            pr "  PyDict_SetItemString (dict, \"%s\", value);\n" name;
            pr "  Py_DECREF (value);\n"
        | name, FInt32 ->
            pr "  value = PyLong_FromLong (%s->%s);\n" typ name;
            pr "  if (value == NULL)\n";
            pr "    goto err;\n";
            pr "  PyDict_SetItemString (dict, \"%s\", value);\n" name;
            pr "  Py_DECREF (value);\n"
        | name, FOptPercent ->
            pr "  if (%s->%s >= 0) {\n" typ name;
            pr "    value = PyFloat_FromDouble ((double) %s->%s);\n" typ name;
            pr "    if (value == NULL)\n";
            pr "      goto err;\n";
            pr "    PyDict_SetItemString (dict, \"%s\", value);\n" name;
            pr "    Py_DECREF (value);\n";
            pr "  }\n";
            pr "  else {\n";
            pr "    Py_INCREF (Py_None);\n";
            pr "    PyDict_SetItemString (dict, \"%s\", Py_None);\n" name;
            pr "  }\n"
        | name, FChar ->
            pr "  value = guestfs_int_py_fromstringsize (&%s->%s, 1);\n"
              typ name;
            pr "  if (value == NULL)\n";
            pr "    goto err;\n";
            pr "  PyDict_SetItemString (dict, \"%s\", value);\n" name;
            pr "  Py_DECREF (value);\n"
      ) cols;
      pr "  return dict;\n";
      pr " err:\n";
      pr "  Py_CLEAR (dict);\n";
      pr "  return NULL;\n";
      pr "};\n";
      pr "#endif\n";
      pr "\n";

  ) external_structs;

  (* Emit a put_TYPE_list function definition only if that function is used. *)
  List.iter (
    function
    | typ, (RStructListOnly | RStructAndList) ->
        (* generate the function for typ *)
        emit_put_list_function typ
    | typ, _ -> () (* empty *)
  ) (rstructs_used_by (actions |> external_functions));

and generate_python_actions actions () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <config.h>

/* It is safe to call deprecated functions from this file. */
#define GUESTFS_NO_WARN_DEPRECATED
#undef GUESTFS_NO_DEPRECATED

#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

#include \"actions.h\"

";

  List.iter (
    fun { name; style = (ret, args, optargs as style);
          blocking; c_name; c_function; c_optarg_prefix } ->
      pr "#ifdef GUESTFS_HAVE_%s\n" (String.uppercase_ascii c_name);
      pr "PyObject *\n";
      pr "guestfs_int_py_%s (PyObject *self, PyObject *args)\n" name;
      pr "{\n";

      pr "  PyObject *py_g;\n";
      pr "  guestfs_h *g;\n";
      pr "  PyObject *py_r = NULL;\n";

      if optargs <> [] then (
        pr "  struct %s optargs_s;\n" c_function;
        pr "  struct %s *optargs = &optargs_s;\n" c_function;
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
        | String (_, n) ->
            pr "  const char *%s;\n" n
        | OptString n -> pr "  const char *%s;\n" n
        | BufferIn n ->
            pr "  const char *%s;\n" n;
            pr "  Py_ssize_t %s_size;\n" n
        | StringList (_, n) ->
            pr "  PyObject *py_%s;\n" n;
            pr "  char **%s = NULL;\n" n
        | Bool n -> pr "  int %s;\n" n
        | Int n -> pr "  int %s;\n" n
        | Int64 n -> pr "  long long %s;\n" n
        | Pointer (t, n) ->
            pr "  void * /* %s */ %s;\n" t n;
            pr "  PyObject *%s_long;\n" n
      ) args;

      (* Fetch the optional arguments as objects, so we can detect
       * if they are 'None'.
       *)
      List.iter (
        fun optarg ->
          pr "  PyObject *py_%s;\n" (name_of_optargt optarg)
      ) optargs;

      pr "\n";

      if optargs <> [] then (
        pr "  optargs_s.bitmask = 0;\n";
        pr "\n"
      );

      (* Convert the required parameters. *)
      pr "  if (!PyArg_ParseTuple (args, (char *) \"O";
      List.iter (
        function
        | String _ -> pr "s"
        | OptString _ -> pr "z"
        | StringList _ -> pr "O"
        | Bool _ -> pr "i" (* XXX Python has booleans? *)
        | Int _ -> pr "i"
        | Int64 _ ->
            (* XXX Whoever thought it was a good idea to
             * emulate C's int/long/long long in Python?
             *)
            pr "L"
        | Pointer _ -> pr "O"
        | BufferIn _ -> pr "s#"
      ) args;

      (* Optional parameters.  All objects, so we can detect None. *)
      List.iter (fun _ -> pr "O") optargs;

      pr ":guestfs_%s\",\n" name;
      pr "                         &py_g";
      List.iter (
        function
        | String (_, n) -> pr ", &%s" n
        | OptString n -> pr ", &%s" n
        | StringList (_, n) -> pr ", &py_%s" n
        | Bool n -> pr ", &%s" n
        | Int n -> pr ", &%s" n
        | Int64 n -> pr ", &%s" n
        | Pointer (_, n) -> pr ", &%s_long" n
        | BufferIn n -> pr ", &%s, &%s_size" n n
      ) args;

      List.iter (
        fun optarg ->
          pr ", &py_%s" (name_of_optargt optarg)
      ) optargs;

      pr "))\n";
      pr "    goto out;\n";

      pr "  g = get_handle (py_g);\n";
      List.iter (
        function
        | String _ | OptString _ | Bool _ | Int _ | Int64 _
        | BufferIn _ -> ()
        | StringList (_, n) ->
            pr "  %s = guestfs_int_py_get_string_list (py_%s);\n" n n;
            pr "  if (!%s) goto out;\n" n
        | Pointer (_, n) ->
            pr "  %s = PyLong_AsVoidPtr (%s_long);\n" n n
      ) args;

      pr "\n";

      if optargs <> [] then (
        List.iter (
          fun optarg ->
            let n = name_of_optargt optarg in
            let uc_n = String.uppercase_ascii n in
            pr "#ifdef %s_%s_BITMASK\n" c_optarg_prefix uc_n;
            pr "  if (py_%s != Py_None) {\n" n;
            pr "    optargs_s.bitmask |= %s_%s_BITMASK;\n" c_optarg_prefix uc_n;
            (match optarg with
            | OBool _ | OInt _ ->
              pr "    optargs_s.%s = PyLong_AsLong (py_%s);\n" n n;
              pr "    if (PyErr_Occurred ()) goto out;\n"
            | OInt64 _ ->
              pr "    optargs_s.%s = PyLong_AsLongLong (py_%s);\n" n n;
              pr "    if (PyErr_Occurred ()) goto out;\n"
            | OString _ ->
              pr "    optargs_s.%s = guestfs_int_py_asstring (py_%s);\n" n n
            | OStringList _ ->
              pr "    optargs_s.%s = guestfs_int_py_get_string_list (py_%s);\n" n n;
              pr "    if (!optargs_s.%s) goto out;\n" n;
            );
            pr "  }\n";
            pr "#endif\n"
        ) optargs;
        pr "\n"
      );

      if blocking then
        pr "  Py_BEGIN_ALLOW_THREADS\n";
      pr "  r = %s " c_function;
      generate_c_call_args ~handle:"g" style;
      pr ";\n";
      if blocking then
        pr "  Py_END_ALLOW_THREADS\n";
      pr "\n";

      (match errcode_of_ret ret with
       | `CannotReturnError -> ()
       | `ErrorIsMinusOne ->
           pr "  if (r == -1) {\n";
           pr "    PyErr_SetString (PyExc_RuntimeError, guestfs_last_error (g));\n";
           pr "    goto out;\n";
           pr "  }\n"
       | `ErrorIsNULL ->
           pr "  if (r == NULL) {\n";
           pr "    PyErr_SetString (PyExc_RuntimeError, guestfs_last_error (g));\n";
           pr "    goto out;\n";
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
           pr "  py_r = guestfs_int_py_fromstring (r);\n";
           pr "  if (py_r == NULL) goto out;\n";
       | RConstOptString _ ->
           pr "  if (r) {\n";
           pr "    py_r = guestfs_int_py_fromstring (r);\n";
           pr "  } else {\n";
           pr "    Py_INCREF (Py_None);\n";
           pr "    py_r = Py_None;\n";
           pr "  }\n";
           pr "  if (py_r == NULL) goto out;\n";
       | RString _ ->
           pr "  py_r = guestfs_int_py_fromstring (r);\n";
           pr "  free (r);\n";
           pr "  if (py_r == NULL) goto out;\n";
       | RStringList _ ->
           pr "  py_r = guestfs_int_py_put_string_list (r);\n";
           pr "  guestfs_int_free_string_list (r);\n";
           pr "  if (py_r == NULL) goto out;\n";
       | RStruct (_, typ) ->
           pr "  py_r = guestfs_int_py_put_%s (r);\n" typ;
           pr "  guestfs_free_%s (r);\n" typ;
           pr "  if (py_r == NULL) goto out;\n";
       | RStructList (_, typ) ->
           pr "  py_r = guestfs_int_py_put_%s_list (r);\n" typ;
           pr "  guestfs_free_%s_list (r);\n" typ;
           pr "  if (py_r == NULL) goto out;\n";
       | RHashtable _ ->
           pr "  py_r = guestfs_int_py_put_table (r);\n";
           pr "  guestfs_int_free_string_list (r);\n";
           pr "  if (py_r == NULL) goto out;\n";
       | RBufferOut _ ->
           pr "  py_r = PyBytes_FromStringAndSize (r, size);\n";
           pr "  free (r);\n";
           pr "  if (py_r == NULL) goto out;\n";
      );

      (* As this is the non-error path, clear the Python error
       * indicator flag in case it was set accidentally somewhere in
       * the function.  Since we are not returning an error indication
       * to the caller, having it set would risk the error popping up
       * at random later in the interpreter.
       *)
      pr "\n";
      pr "  PyErr_Clear ();\n";
      pr " out:\n";

      List.iter (
        function
        | String _ | OptString _ | Bool _ | Int _ | Int64 _
        | BufferIn _ | Pointer _ -> ()
        | StringList (_, n) ->
            pr "  free (%s);\n" n
      ) args;

      List.iter (
        function
        | OBool _ | OInt _ | OInt64 _ | OString _ -> ()
        | OStringList n ->
          let uc_n = String.uppercase_ascii n in
          pr "#ifdef %s_%s_BITMASK\n" c_optarg_prefix uc_n;
          pr "  if (py_%s != Py_None && (optargs_s.bitmask & %s_%s_BITMASK) != 0)\n"
            n c_optarg_prefix uc_n;
          pr "    free ((char **) optargs_s.%s);\n" n;
          pr "#endif\n"
      ) optargs;

      pr "  return py_r;\n";
      pr "}\n";
      pr "#endif\n";
      pr "\n"
  ) (actions |> external_functions |> sort)

and generate_python_module () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

#include \"actions.h\"

";

  (* Table of functions. *)
  pr "static PyMethodDef methods[] = {\n";
  pr "  { (char *) \"create\", guestfs_int_py_create, METH_VARARGS, NULL },\n";
  pr "  { (char *) \"close\", guestfs_int_py_close, METH_VARARGS, NULL },\n";
  pr "  { (char *) \"set_event_callback\",\n";
  pr "    guestfs_int_py_set_event_callback, METH_VARARGS, NULL },\n";
  pr "  { (char *) \"delete_event_callback\",\n";
  pr "    guestfs_int_py_delete_event_callback, METH_VARARGS, NULL },\n";
  pr "  { (char *) \"event_to_string\",\n";
  pr "    guestfs_int_py_event_to_string, METH_VARARGS, NULL },\n";
  List.iter (
    fun { name; c_name } ->
      pr "#ifdef GUESTFS_HAVE_%s\n" (String.uppercase_ascii c_name);
      pr "  { (char *) \"%s\", guestfs_int_py_%s, METH_VARARGS, NULL },\n"
        name name;
      pr "#endif\n"
  ) (actions |> external_functions |> sort);
  pr "  { NULL, NULL, 0, NULL }\n";
  pr "};\n";
  pr "\n";

  (* Init function. *)
  pr "\
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

static PyObject *
moduleinit (void)
{
  PyObject *m;

  m = PyModule_Create (&moduledef);

  if (m != NULL)
    guestfs_int_py_extend_module (m);

  return m; /* m might be NULL if module init failed */
}

extern PyMODINIT_FUNC PyInit_libguestfsmod (void);

PyMODINIT_FUNC
PyInit_libguestfsmod (void)
{
  return moduleinit ();
}
"

(* Generate Python module. *)
and generate_python_py () =
  (* This has to appear very near the top of the file, before the large
   * header.
   *)
  pr "# coding: utf-8\n";

  generate_header HashStyle LGPLv2plus;

  pr "\
\"\"\"Python bindings for libguestfs

import guestfs
g = guestfs.GuestFS(python_return_dict=True)
g.add_drive_opts(\"guest.img\", format=\"raw\")
g.launch()
parts = g.list_partitions()

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
g = guestfs.GuestFS()
g.add_drive_opts(\"guest.img\", format=\"raw\")

# Launch the qemu subprocess and wait for it to become ready:
g.launch()

# Now you can issue commands, for example:
logvols = g.lvs()

\"\"\"

import os
import sys
import libguestfsmod
from typing import Union, List, Tuple, Optional

";

  List.iter (
    fun (name, bitmask) ->
      pr "EVENT_%s = 0x%x\n" (String.uppercase_ascii name) bitmask
  ) events;
  pr "EVENT_ALL = 0x%x\n" all_events_bitmask;
  pr "\n";
  pr "\

def event_to_string(events):
    \"\"\"Return a printable string from an event or event bitmask\"\"\"
    return libguestfsmod.event_to_string(events)


class ClosedHandle(ValueError):
    pass


class GuestFS(object):
    \"\"\"Instances of this class are libguestfs API handles.\"\"\"

    def __init__(self, python_return_dict=False,
                 environment=True, close_on_exit=True):
        \"\"\"Create a new libguestfs handle.

        Note about \"python_return_dict\" flag:

        Setting this flag to 'True' causes all functions
        that internally return hashes to return a dict.  This is
        natural for Python, and all new code should use
        python_return_dict=True.

        If this flag is not present then hashes are returned
        as lists of pairs.  This was the only possible behaviour
        in libguestfs <= 1.20.
        \"\"\"
        flags = 0
        if not environment:
            flags |= libguestfsmod.GUESTFS_CREATE_NO_ENVIRONMENT
        if not close_on_exit:
            flags |= libguestfsmod.GUESTFS_CREATE_NO_CLOSE_ON_EXIT
        self._o = libguestfsmod.create(flags)
        self._python_return_dict = python_return_dict

        # If we don't do this, the program name is always set to 'python'.
        program = os.path.basename(sys.argv[0])
        libguestfsmod.set_program(self._o, program)

    def __del__(self):
        if self._o:
            libguestfsmod.close(self._o)

    def _check_not_closed(self):
        if not self._o:
            raise ClosedHandle(\"GuestFS: method called on closed handle\")

    def _maybe_convert_to_dict(self, r):
        if self._python_return_dict:
            r = dict(r)
        return r

    def close(self):
        \"\"\"Explicitly close the guestfs handle.

        The handle is closed implicitly when its reference count goes
        to zero (eg. when it goes out of scope or the program ends).

        This call is only needed if you want to force the handle to
        close now.  After calling this, the program must not call
        any method on the handle (except the implicit call to
        __del__ which happens when the final reference is cleaned up).
        \"\"\"
        self._check_not_closed()
        libguestfsmod.close(self._o)
        self._o = None

    def set_event_callback(self, cb, event_bitmask):
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
        self._check_not_closed()
        return libguestfsmod.set_event_callback(self._o, cb, event_bitmask)

    def delete_event_callback(self, event_handle):
        \"\"\"Delete an event callback.\"\"\"
        self._check_not_closed()
        libguestfsmod.delete_event_callback(self._o, event_handle)
";

  let map_join f l =
    String.concat "" (List.map f l)
  in

  List.iter (
    fun f ->
      let ret, args, optargs = f.style in
      let len_name = String.length f.name in
      let ret_type_hint =
        match ret with
        | RErr -> "None"
        | RInt _ | RInt64 _ -> "int"
        | RBool _ -> "bool"
        | RConstOptString _ -> "Optional[str]"
        | RConstString _ | RString _ -> "str"
        | RBufferOut _ -> "bytes"
        | RStringList _ -> "List[str]"
        | RStruct _ -> "dict"
        | RStructList _ -> "List[dict]"
        | RHashtable _ -> "Union[List[Tuple[str, str]], dict]" in
      let type_hint_of_argt arg =
        match arg with
        | String _ -> ": str"
        | OptString _ -> ": Optional[str]"
        | Bool _ -> ": bool"
        | Int _ | Int64 _ -> ": int"
        | BufferIn _ -> ": bytes"
        | StringList _ -> ": List[str]"
        | Pointer _ -> ""
      in
      let type_hint_of_optargt optarg =
        match optarg with
        | OBool _ -> "bool"
        | OInt _ | OInt64 _ -> "int"
        | OString _ -> "str"
        | OStringList _ -> "List[str]"
      in
      let decl_string =
        "self" ^
        map_join (fun arg ->sprintf ", %s%s" (name_of_argt arg) (type_hint_of_argt arg))
          args ^
        map_join (fun optarg -> sprintf ", %s: Optional[%s] = None" (name_of_optargt optarg) (type_hint_of_optargt optarg))
          optargs ^
        ") -> " ^ ret_type_hint ^ ":" in
      pr "\n";
      pr "    def %s(%s\n"
        f.name (indent_python decl_string (9 + len_name) 78);

      if is_documented f then (
        let doc = String.replace f.longdesc "C<guestfs_" "C<g." in
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
              doc ^ "\n\nThis function returns a hash.  If the GuestFS constructor was called with python_return_dict=True (recommended) then the return value is in fact a Python dict.  Otherwise the return value is a list of pairs of strings, for compatibility with old code." in
        let doc =
          if f.protocol_limit_warning then
            doc ^ "\n\n" ^ protocol_limit_warning
          else doc in
        let doc =
          match deprecation_notice f with
          | None -> doc
          | Some txt -> doc ^ "\n\n" ^ txt in
        let doc =
          match f.optional with
          | None -> doc
          | Some opt ->
            doc ^ sprintf "\n\nThis function depends on the feature C<%s>.  See also C<g.feature-available>." opt in
        let doc = pod2text ~width:60 f.name doc in
        let doc = List.map (fun line -> String.replace line "\\" "\\\\") doc in
        let doc =
          match doc with
          | [] -> ""
          | [line] -> line
          | hd :: tl ->
            let endpos = List.length tl - 1 in
            (* Add indentation spaces, but only if the line is not empty or
             * it is not the last one (since there will be the 3 dobule-quotes
             * at the end.
             *)
            let lines =
              List.mapi (
                fun lineno line ->
                  if line = "" && lineno <> endpos then
                    ""
                  else
                    "        " ^ line
              ) tl in
            hd ^ "\n" ^ (String.concat "\n" lines) in
        pr "        \"\"\"%s\"\"\"\n" doc;
      );
      (* Callers might pass in iterables instead of plain lists;
       * convert those to plain lists because the C side of things
       * cannot deal with iterables.  (RHBZ#693306).
       *)
      List.iter (
        function
        | String _ | OptString _ | Bool _ | Int _ | Int64 _
        | BufferIn _ -> ()
        | StringList (_, n) ->
          pr "        %s = list(%s)\n" n n
        | Pointer (_, n) ->
          pr "        %s = %s.c_pointer()\n" n n
      ) args;
      pr "        self._check_not_closed()\n";
      (match f.deprecated_by with
      | Not_deprecated -> ()
      | Replaced_by alt ->
        pr "        import warnings\n";
        pr "        warnings.warn(\"use GuestFS.%s() \"\n" alt;
        pr "                      \"instead of GuestFS.%s()\",\n" f.name;
        pr "                      DeprecationWarning, stacklevel=2)\n";
      | Deprecated_no_replacement ->
        pr "        import warnings\n";
        pr "        warnings.warn(\"do not use GuestFS.%s()\",\n" f.name;
        pr "                      DeprecationWarning, stacklevel=2)\n";
      );
      let function_string =
        "self._o" ^
        map_join (fun arg -> sprintf ", %s" (name_of_argt arg))
          (args @ args_of_optargs optargs) in
      pr "        r = libguestfsmod.%s(%s)\n"
        f.name (indent_python function_string (27 + len_name) 78);

      (* For RHashtable, if self._python_return_dict=True then we
       * have to convert the result to a dict.
       *)
      (match ret with
      | RHashtable _ ->
        pr "        r = self._maybe_convert_to_dict(r)\n";
      | _ -> ()
      );

      pr "        return r\n";

      (* Aliases. *)
      List.iter (
        fun alias ->
          pr "\n    %s = %s\n" alias f.name
      ) f.non_c_aliases
  ) (actions |> external_functions |> sort)

and indent_python str indent columns =
  let rec loop str endpos =
    let len = String.length str in
    if len + indent > columns then
      try
        let pos = String.rindex_from str endpos ',' in
        if pos + indent > columns then
          loop str (pos - 1)
        else (
          let rest = String.sub str (pos + 2) (len - pos - 2) in
          String.sub str 0 pos :: loop rest (String.length rest - 1)
        )
      with Not_found ->
        [str]
    else
      [str]
  in
  let lines = loop str (String.length str - 1) in
  String.concat (",\n" ^ String.make indent ' ') lines
