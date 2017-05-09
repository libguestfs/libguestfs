/* libguestfs python bindings
 * Copyright (C) 2009-2017 Red Hat Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

/**
 * This file contains a small number of functions that are written by
 * hand.  The majority of the bindings are generated (see
 * F<python/actions-*.c>).
 */

/* This has to be included first, else definitions conflict with
 * glibc header files.  Python is broken.
 */
#define PY_SSIZE_T_CLEAN 1
#include <Python.h>

#include <config.h>

#include <stdio.h>
#include <stdlib.h>

#include "actions.h"

static PyObject **get_all_event_callbacks (guestfs_h *g, size_t *len_rtn);

void
guestfs_int_py_extend_module (PyObject *module)
{
   PyModule_AddIntMacro(module, GUESTFS_CREATE_NO_ENVIRONMENT);
   PyModule_AddIntMacro(module, GUESTFS_CREATE_NO_CLOSE_ON_EXIT);
}

PyObject *
guestfs_int_py_create (PyObject *self, PyObject *args)
{
  guestfs_h *g;
  unsigned flags;

  if (!PyArg_ParseTuple (args, (char *) "I:guestfs_create", &flags))
    return NULL;
  g = guestfs_create_flags (flags);
  if (g == NULL) {
    PyErr_SetString (PyExc_RuntimeError,
                     "guestfs.create: failed to allocate handle");
    return NULL;
  }
  guestfs_set_error_handler (g, NULL, NULL);
  /* This can return NULL, but in that case put_handle will have
   * set the Python error string.
   */
  return put_handle (g);
}

PyObject *
guestfs_int_py_close (PyObject *self, PyObject *args)
{
  PyThreadState *py_save = NULL;
  PyObject *py_g;
  guestfs_h *g;
  size_t len;
  PyObject **callbacks;

  if (!PyArg_ParseTuple (args, (char *) "O:guestfs_close", &py_g))
    return NULL;
  g = get_handle (py_g);

  /* As in the OCaml bindings, there is a hard to solve case where the
   * caller can delete a callback from within the callback, resulting
   * in a double-free here.  XXX
   *
   * Take care of the result of get_all_event_callbacks: NULL can be
   * both an error (and some PyErr_* was called), and no events.
   * 'len' is specifically 0 only in the latter case, so filter that
   * out.
   */
  callbacks = get_all_event_callbacks (g, &len);
  if (len != 0 && callbacks == NULL)
    return NULL;

  if (PyEval_ThreadsInitialized ())
    py_save = PyEval_SaveThread ();
  guestfs_close (g);
  if (PyEval_ThreadsInitialized ())
    PyEval_RestoreThread (py_save);

  if (len > 0) {
    size_t i;
    for (i = 0; i < len; ++i)
      Py_XDECREF (callbacks[i]);
    free (callbacks);
  }

  Py_INCREF (Py_None);
  return Py_None;
}

/* http://docs.python.org/release/2.5.2/ext/callingPython.html */
static void
guestfs_int_py_event_callback_wrapper (guestfs_h *g,
                                   void *callback,
                                   uint64_t event,
                                   int event_handle,
                                   int flags,
                                   const char *buf, size_t buf_len,
                                   const uint64_t *array, size_t array_len)
{
  PyGILState_STATE py_save = PyGILState_UNLOCKED;
  PyObject *py_callback = callback;
  PyObject *py_array;
  PyObject *args;
  PyObject *a;
  size_t i;
  PyObject *py_r;

  py_array = PyList_New (array_len);
  for (i = 0; i < array_len; ++i) {
    a = PyLong_FromLongLong (array[i]);
    PyList_SET_ITEM (py_array, i, a);
  }

  /* XXX As with Perl we don't pass the guestfs_h handle here. */
  args = Py_BuildValue ("(Kis#O)",
                        (unsigned PY_LONG_LONG) event, event_handle,
                        buf, buf_len, py_array);

  if (PyEval_ThreadsInitialized ())
    py_save = PyGILState_Ensure ();

  py_r = PyEval_CallObject (py_callback, args);

  if (PyEval_ThreadsInitialized ())
    PyGILState_Release (py_save);

  Py_DECREF (args);

  if (py_r != NULL)
    Py_DECREF (py_r);
  else
    /* Callback threw an exception: print it. */
    PyErr_PrintEx (0);
}

PyObject *
guestfs_int_py_set_event_callback (PyObject *self, PyObject *args)
{
  PyObject *py_g;
  guestfs_h *g;
  PyObject *py_callback;
  unsigned PY_LONG_LONG events;
  int eh;
  PyObject *py_eh;
  char key[64];

  if (!PyArg_ParseTuple (args, (char *) "OOK:guestfs_set_event_callback",
                         &py_g, &py_callback, &events))
    return NULL;

  if (!PyCallable_Check (py_callback)) {
    PyErr_SetString (PyExc_TypeError,
                     "callback parameter is not callable "
                     "(eg. lambda or function)");
    return NULL;
  }

  g = get_handle (py_g);

  eh = guestfs_set_event_callback (g, guestfs_int_py_event_callback_wrapper,
                                   events, 0, py_callback);
  if (eh == -1) {
    PyErr_SetString (PyExc_RuntimeError, guestfs_last_error (g));
    return NULL;
  }

  /* Increase the refcount for this callback since we are storing it
   * in the opaque C libguestfs handle.  We need to remember that we
   * did this, so we can decrease the refcount for all undeleted
   * callbacks left around at close time (see guestfs_int_py_close).
   */
  Py_XINCREF (py_callback);

  snprintf (key, sizeof key, "_python_event_%d", eh);
  guestfs_set_private (g, key, py_callback);

  py_eh = PyLong_FromLong ((long) eh);
  return py_eh;
}

PyObject *
guestfs_int_py_delete_event_callback (PyObject *self, PyObject *args)
{
  PyObject *py_g;
  guestfs_h *g;
  int eh;
  PyObject *py_callback;
  char key[64];

  if (!PyArg_ParseTuple (args, (char *) "Oi:guestfs_delete_event_callback",
                         &py_g, &eh))
    return NULL;
  g = get_handle (py_g);

  snprintf (key, sizeof key, "_python_event_%d", eh);
  py_callback = guestfs_get_private (g, key);
  if (py_callback) {
    Py_XDECREF (py_callback);
    guestfs_set_private (g, key, NULL);
    guestfs_delete_event_callback (g, eh);
  }

  Py_INCREF (Py_None);
  return Py_None;
}

PyObject *
guestfs_int_py_event_to_string (PyObject *self, PyObject *args)
{
  unsigned PY_LONG_LONG events;
  char *str;
  PyObject *py_r;

  if (!PyArg_ParseTuple (args, (char *) "K", &events))
    return NULL;

  str = guestfs_event_to_string (events);
  if (str == NULL) {
    PyErr_SetString (PyExc_RuntimeError, strerror (errno));
    return NULL;
  }

  py_r = guestfs_int_py_fromstring (str);
  free (str);

  return py_r;
}

static PyObject **
get_all_event_callbacks (guestfs_h *g, size_t *len_rtn)
{
  PyObject **r;
  size_t i;
  const char *key;
  PyObject *cb;

  /* Count the length of the array that will be needed. */
  *len_rtn = 0;
  cb = guestfs_first_private (g, &key);
  while (cb != NULL) {
    if (strncmp (key, "_python_event_", strlen ("_python_event_")) == 0)
      (*len_rtn)++;
    cb = guestfs_next_private (g, &key);
  }

  /* No events, so no need to allocate anything. */
  if (*len_rtn == 0)
    return NULL;

  /* Copy them into the return array. */
  r = malloc (sizeof (PyObject *) * (*len_rtn));
  if (r == NULL) {
    PyErr_SetNone (PyExc_MemoryError);
    return NULL;
  }

  i = 0;
  cb = guestfs_first_private (g, &key);
  while (cb != NULL) {
    if (strncmp (key, "_python_event_", strlen ("_python_event_")) == 0) {
      r[i] = cb;
      i++;
    }
    cb = guestfs_next_private (g, &key);
  }

  return r;
}

/* This list should be freed (but not the strings) after use. */
char **
guestfs_int_py_get_string_list (PyObject *obj)
{
  size_t i, len;
  char **r;

  assert (obj);

  if (!PyList_Check (obj)) {
    PyErr_SetString (PyExc_RuntimeError, "expecting a list parameter");
    return NULL;
  }

  Py_ssize_t slen = PyList_Size (obj);
  if (slen == -1) {
    PyErr_SetString (PyExc_RuntimeError, "get_string_list: PyList_Size failure");
    return NULL;
  }
  len = (size_t) slen;
  r = malloc (sizeof (char *) * (len+1));
  if (r == NULL) {
    PyErr_SetString (PyExc_RuntimeError, "get_string_list: out of memory");
    return NULL;
  }

  for (i = 0; i < len; ++i)
    r[i] = guestfs_int_py_asstring (PyList_GetItem (obj, i));
  r[len] = NULL;

  return r;
}

PyObject *
guestfs_int_py_put_string_list (char * const * const argv)
{
  PyObject *list;
  size_t argc, i;

  for (argc = 0; argv[argc] != NULL; ++argc)
    ;

  list = PyList_New (argc);
  for (i = 0; i < argc; ++i) {
    PyList_SetItem (list, i, guestfs_int_py_fromstring (argv[i]));
  }

  return list;
}

PyObject *
guestfs_int_py_put_table (char * const * const argv)
{
  PyObject *list, *item;
  size_t argc, i;

  for (argc = 0; argv[argc] != NULL; ++argc)
    ;

  list = PyList_New (argc >> 1);
  for (i = 0; i < argc; i += 2) {
    item = PyTuple_New (2);
    PyTuple_SetItem (item, 0, guestfs_int_py_fromstring (argv[i]));
    PyTuple_SetItem (item, 1, guestfs_int_py_fromstring (argv[i+1]));
    PyList_SetItem (list, i >> 1, item);
  }

  return list;
}

PyObject *
guestfs_int_py_fromstring (const char *str)
{
#ifdef HAVE_PYSTRING_ASSTRING
  return PyString_FromString (str);
#else
  return PyUnicode_FromString (str);
#endif
}

PyObject *
guestfs_int_py_fromstringsize (const char *str, size_t size)
{
#ifdef HAVE_PYSTRING_ASSTRING
  return PyString_FromStringAndSize (str, size);
#else
  return PyUnicode_FromStringAndSize (str, size);
#endif
}

char *
guestfs_int_py_asstring (PyObject *obj)
{
#ifdef HAVE_PYSTRING_ASSTRING
  return PyString_AsString (obj);
#else
  PyObject *bytes = PyUnicode_AsUTF8String (obj);
  return PyBytes_AS_STRING (bytes);
#endif
}
