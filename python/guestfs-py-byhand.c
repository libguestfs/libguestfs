/* libguestfs python bindings
 * Copyright (C) 2009-2011 Red Hat Inc.
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
#include <assert.h>

#include "guestfs-py.h"

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

  if (!PyArg_ParseTuple (args, (char *) "O:guestfs_close", &py_g))
    return NULL;
  g = get_handle (py_g);

  if (PyEval_ThreadsInitialized ())
    py_save = PyEval_SaveThread ();
  guestfs_close (g);
  if (PyEval_ThreadsInitialized ())
    PyEval_RestoreThread (py_save);

  Py_INCREF (Py_None);
  return Py_None;
}
