/* libguestfs Java bindings.
 * Copyright (C) 2009-2023 Red Hat Inc.
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

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>

#include "com_redhat_et_libguestfs_GuestFS.h"
#include "guestfs.h"
#include "guestfs-utils.h"

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

static struct callback_data **get_all_event_callbacks (JNIEnv *env, guestfs_h *g, size_t *len_rtn);

/* Note that this function returns.  The exception is not thrown
 * until after the wrapper function returns.
 */
static void
throw_exception (JNIEnv *env, const char *msg)
{
  jclass cl;
  cl = (*env)->FindClass (env,
                          "com/redhat/et/libguestfs/LibGuestFSException");
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
                          "com/redhat/et/libguestfs/LibGuestFSOutOfMemory");
  (*env)->ThrowNew (env, cl, msg);
}

JNIEXPORT jlong JNICALL
Java_com_redhat_et_libguestfs_GuestFS__1create (JNIEnv *env,
                                                jobject obj_unused, jint flags)
{
  guestfs_h *g;

  g = guestfs_create_flags ((int) flags);
  if (g == NULL) {
    throw_exception (env, "GuestFS.create: failed to allocate handle");
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
  size_t len;
  struct callback_data **data;

  /* There is a nasty, difficult to solve case here where the
   * user deletes events in one of the callbacks that we are
   * about to invoke, resulting in a double-free.  XXX
   */
  data = get_all_event_callbacks (env, g, &len);

  guestfs_close (g);

  if (data && len > 0) {
    size_t i;
    for (i = 0; i < len; ++i) {
      (*env)->DeleteGlobalRef (env, data[i]->callback);
      free (data[i]);
    }
    free (data);
  }
}

/* See EventCallback interface. */
#define METHOD_NAME "event"
#define METHOD_SIGNATURE "(JILjava/lang/String;[J)V"

static void
java_callback (guestfs_h *g,
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
      fprintf (stderr, "%s: event %" PRIu64 " (eh %d) ignored because the thread is not attached to the JVM.  This can happen when libguestfs handles are cleaned up at program exit after the JVM has been destroyed.\n",
               __func__, event, event_handle);
      return;

    case JNI_EVERSION:
      fprintf (stderr, "%s: event %" PRIu64 " (eh %d) failed because the JVM version is too old.  JVM >= 1.6 is required.\n",
               __func__, event, event_handle);
      return;

    default:
      fprintf (stderr, "%s: jvm->GetEnv failed! (JNI_* error code = %d)\n",
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
    throw_exception (env, "GuestFS.set_event_callback: callback class does not implement the EventCallback interface");
    return -1;
  }

  data = malloc (sizeof *data);
  if (data == NULL) {
    throw_out_of_memory (env, "malloc");
    return -1;
  }
  (*env)->GetJavaVM (env, &data->jvm);
  data->method = method;

  r = guestfs_set_event_callback (g, java_callback,
                                  (uint64_t) jevents, 0, data);
  if (r == -1) {
    free (data);
    throw_exception (env, guestfs_last_error (g));
    return -1;
  }

  /* Register jcallback as a global reference so the GC won't free it. */
  data->callback = (*env)->NewGlobalRef (env, jcallback);

  /* Store 'data' in the handle, so we can free it at some point. */
  snprintf (key, sizeof key, "_java_event_%d", r);
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

  snprintf (key, sizeof key, "_java_event_%d", eh);

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
    perror ("guestfs_event_to_string");
    return NULL;
  }

  jr = (*env)->NewStringUTF (env, str);
  free (str);

  return jr;
}

static struct callback_data **
get_all_event_callbacks (JNIEnv *env, guestfs_h *g, size_t *len_rtn)
{
  struct callback_data **r;
  size_t i;
  const char *key;
  struct callback_data *data;

  /* Count the length of the array that will be needed. */
  *len_rtn = 0;
  data = guestfs_first_private (g, &key);
  while (data != NULL) {
    if (strncmp (key, "_java_event_", strlen ("_java_event_")) == 0)
      (*len_rtn)++;
    data = guestfs_next_private (g, &key);
  }

  /* No events, so no need to allocate anything. */
  if (*len_rtn == 0)
    return NULL;

  /* Copy them into the return array. */
  r = malloc (sizeof (struct callback_data *) * (*len_rtn));
  if (r == NULL) {
    throw_out_of_memory (env, "malloc");
    return NULL;
  }

  i = 0;
  data = guestfs_first_private (g, &key);
  while (data != NULL) {
    if (strncmp (key, "_java_event_", strlen ("_java_event_")) == 0) {
      r[i] = data;
      i++;
    }
    data = guestfs_next_private (g, &key);
  }

  return r;
}
