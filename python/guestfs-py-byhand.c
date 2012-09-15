/* libguestfs python bindings
 * Copyright (C) 2009-2012 Red Hat Inc.
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

/* This file contains a small number of functions that are written by
 * hand.  The majority of the bindings are generated (see
 * guestfs-py.c).
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>

#include "guestfs-py.h"

static PyObject **get_all_event_callbacks (guestfs_h *g, size_t *len_rtn);

PyObject *
py_guestfs_create (PyObject *self, PyObject *args)
{
  guestfs_h *g;

  g = guestfs_create ();
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
py_guestfs_close (PyObject *self, PyObject *args)
{
  PyThreadState *py_save = NULL;
  PyObject *py_g;
  guestfs_h *g;
  size_t i, len;
  PyObject **callbacks;

  if (!PyArg_ParseTuple (args, (char *) "O:guestfs_close", &py_g))
    return NULL;
  g = get_handle (py_g);

  /* As in the OCaml bindings, there is a hard to solve case where the
   * caller can delete a callback from within the callback, resulting
   * in a double-free here.  XXX
   */
  callbacks = get_all_event_callbacks (g, &len);

  if (PyEval_ThreadsInitialized ())
    py_save = PyEval_SaveThread ();
  guestfs_close (g);
  if (PyEval_ThreadsInitialized ())
    PyEval_RestoreThread (py_save);

  for (i = 0; i < len; ++i)
    Py_XDECREF (callbacks[i]);
  free (callbacks);

  Py_INCREF (Py_None);
  return Py_None;
}

/* http://docs.python.org/release/2.5.2/ext/callingPython.html */
static void
py_guestfs_event_callback_wrapper (guestfs_h *g,
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
py_guestfs_set_event_callback (PyObject *self, PyObject *args)
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

  eh = guestfs_set_event_callback (g, py_guestfs_event_callback_wrapper,
                                   events, 0, py_callback);
  if (eh == -1) {
    PyErr_SetString (PyExc_RuntimeError, guestfs_last_error (g));
    return NULL;
  }

  /* Increase the refcount for this callback since we are storing it
   * in the opaque C libguestfs handle.  We need to remember that we
   * did this, so we can decrease the refcount for all undeleted
   * callbacks left around at close time (see py_guestfs_close).
   */
  Py_XINCREF (py_callback);

  snprintf (key, sizeof key, "_python_event_%d", eh);
  guestfs_set_private (g, key, py_callback);

  py_eh = PyLong_FromLong ((long) eh);
  return py_eh;
}

PyObject *
py_guestfs_delete_event_callback (PyObject *self, PyObject *args)
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

  /* Copy them into the return array. */
  r = guestfs_safe_malloc (g, sizeof (PyObject *) * (*len_rtn));

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
