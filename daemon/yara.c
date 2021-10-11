/* libguestfs - the guestfsd daemon
 * Copyright (C) 2016 Red Hat Inc.
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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <fcntl.h>
#include <stdlib.h>
#include <inttypes.h>
#include <string.h>
#include <unistd.h>
#include <stdbool.h>
#include <rpc/types.h>
#include <rpc/xdr.h>
#include <sys/types.h>
#include <sys/stat.h>

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"
#include "guestfs_protocol.h"

#ifdef HAVE_YARA

#include <yara.h>

#ifdef HAVE_ATTRIBUTE_CLEANUP
#define CLEANUP_DESTROY_YARA_COMPILER                           \
  __attribute__((cleanup(cleanup_destroy_yara_compiler)))
#else
#define CLEANUP_DESTROY_YARA_COMPILER
#endif

struct write_callback_data {
  int fd;
  uint64_t written;
};

/* Yara compiled rules. */
static YR_RULES *rules = NULL;
static bool initialized = false;

static int compile_rules_file (const char *);
static void cleanup_destroy_yara_compiler (void *ptr);
static int send_detection_info (const char *, YR_RULE *);

/* Typedefs that effectively strip the pointer derivation from Yara's
 * YR_CALLBACK_FUNC and YR_COMPILER_CALLBACK_FUNC types, using GCC's "typeof"
 * extension.
 */
typedef typeof (*(YR_CALLBACK_FUNC)NULL)          guestfs_yr_callback;
typedef typeof (*(YR_COMPILER_CALLBACK_FUNC)NULL) guestfs_yr_compiler_callback;

/* Declarations of our callback functions expressed in terms of Yara's
 * typedefs. Note: these are *function declarations*.
 */
static guestfs_yr_callback          yara_rules_callback;
static guestfs_yr_compiler_callback compile_error_callback;

/* Has one FileIn parameter.
 * Takes optional arguments, consult optargs_bitmask.
 */
int
do_yara_load (void)
{
  int r;
  CLEANUP_CLOSE int fd = -1;
  char tmpfile[] = "/tmp/yaraXXXXXX";

  fd = mkstemp (tmpfile);
  if (fd == -1) {
    reply_with_perror ("mkstemp");
    return -1;
  }

  r = upload_to_fd (fd, tmpfile);
  if (r == -1) {
    unlink (tmpfile);
    return -1;
  }

  /* Initialize yara only once. */
  if (!initialized) {
    r = yr_initialize ();
    if (r != ERROR_SUCCESS) {
      reply_with_error ("failed initializing yara");
      unlink (tmpfile);
      return -1;
    }

    initialized = true;
  }

  /* Destroy previously loaded rules. */
  if (rules != NULL) {
    yr_rules_destroy (rules);
    rules = NULL;
  }

  /* Try to load the rules as compiled.
   * If their are in source code format, compile them first.
   */
  r = yr_rules_load (tmpfile, &rules);
  if (r == ERROR_INVALID_FILE)
    r = compile_rules_file (tmpfile);

  unlink (tmpfile);

  return (r == ERROR_SUCCESS) ? 0 : -1;
}

int
do_yara_destroy (void)
{
  if (rules == NULL) {
    reply_with_error ("no yara rules loaded");
    return -1;
  }

  yr_rules_destroy (rules);
  rules = NULL;

  return 0;
}

/* Has one FileOut parameter. */
int
do_internal_yara_scan (const char *path)
{
  int r;
  CLEANUP_CLOSE int fd = -1;

  if (rules == NULL) {
    reply_with_error ("no yara rules loaded");
    return -1;
  }

  CHROOT_IN;
  fd = open (path, O_RDONLY|O_CLOEXEC);
  CHROOT_OUT;

  if (fd == -1) {
    reply_with_perror ("%s", path);
    return -1;
  }

  reply (NULL, NULL);  /* Reply message. */

  r = yr_rules_scan_fd (rules, fd, 0, yara_rules_callback, (void *) path, 0);
  if (r == ERROR_SUCCESS)
    r = send_file_end (0);  /* File transfer end. */
  else
    send_file_end (1);  /* Cancel file transfer. */

  return 0;
}

/* Compile source code rules and load them.
 * Return ERROR_SUCCESS on success, Yara error code type on error.
 */
static int
compile_rules_file (const char *rules_path)
{
  int ret;
  CLEANUP_FCLOSE FILE *rule_file = NULL;
  CLEANUP_DESTROY_YARA_COMPILER YR_COMPILER *compiler = NULL;

  ret = yr_compiler_create (&compiler);
  if (ret != ERROR_SUCCESS) {
    reply_with_error ("yr_compiler_create");
    return ret;
  }

  yr_compiler_set_callback (compiler, compile_error_callback, NULL);

  rule_file = fopen (rules_path, "r");
  if (rule_file == NULL) {
    reply_with_error ("unable to open rules file");
    ret = ERROR_COULD_NOT_OPEN_FILE;
    goto err;
  }

  ret = yr_compiler_add_file (compiler, rule_file, NULL, NULL);
  if (ret > 0) {
    reply_with_error ("found %d errors when compiling the rules", ret);
    goto err;
  }

  ret = yr_compiler_get_rules (compiler, &rules);
  if (ret == ERROR_INSUFICIENT_MEMORY) {
    errno = ENOMEM;
    reply_with_perror ("yr_compiler_get_rules");
  }

 err:
#ifndef HAVE_ATTRIBUTE_CLEANUP
  yr_compiler_destroy (compiler);
#endif

  return ret;
}

/* Yara compilation error callback.
 * Reports back the compilation error message.
 * Prints compilation warnings if verbose.
 */
static void
compile_error_callback (int level, const char *name, int line,
                        const YR_RULE *rule, const char *message, void *data)
{
  if (level == YARA_ERROR_LEVEL_ERROR)
    fprintf (stderr, "Yara error (line %d): %s\n", line, message);
  else if (verbose)
    fprintf (stderr, "Yara warning (line %d): %s\n", line, message);
}

/* Yara scan callback, called by yr_rules_scan_file.
 * Return 0 on success, -1 on error.
 */
static int
yara_rules_callback (YR_SCAN_CONTEXT *context, int code, void *message,
                     void *data)
{
  int ret = 0;

  if (code == CALLBACK_MSG_RULE_MATCHING)
    ret = send_detection_info ((const char *)data, (YR_RULE *) message);

  return (ret == 0) ? CALLBACK_CONTINUE : CALLBACK_ERROR;
}

/* Serialize file path and rule name and send it out.
 * Return 0 on success, -1 on error.
 */
static int
send_detection_info (const char *name, YR_RULE *rule)
{
  XDR xdr;
  int r;
  size_t len;
  CLEANUP_FREE char *buf = NULL;
  struct guestfs_int_yara_detection detection;

  detection.yara_name = (char *) name;
  detection.yara_rule = (char *) rule->identifier;

  /* Serialize detection struct. */
  buf = malloc (GUESTFS_MAX_CHUNK_SIZE);
  if (buf == NULL) {
    perror ("malloc");
    return -1;
  }

  xdrmem_create (&xdr, buf, GUESTFS_MAX_CHUNK_SIZE, XDR_ENCODE);

  r = xdr_guestfs_int_yara_detection (&xdr, &detection);
  if (r == 0) {
    perror ("xdr_guestfs_int_yara_detection");
    return -1;
  }

  len = xdr_getpos (&xdr);

  xdr_destroy (&xdr);

  /* Send serialised yara_detection out. */
  return send_file_write (buf, len);
}

/* Clean up yara handle on daemon exit. */
void yara_finalize (void) __attribute__((destructor));

void
yara_finalize (void)
{
  int r;

  if (!initialized)
    return;

  if (rules != NULL) {
    yr_rules_destroy (rules);
    rules = NULL;
  }

  r = yr_finalize ();
  if (r != ERROR_SUCCESS)
    perror ("yr_finalize");

  initialized = false;
}

static void
cleanup_destroy_yara_compiler (void *ptr)
{
  YR_COMPILER *compiler = * (YR_COMPILER **) ptr;

  if (compiler != NULL)
    yr_compiler_destroy (compiler);
}

int
optgroup_libyara_available (void)
{
  return 1;
}

#else   /* !HAVE_YARA */

OPTGROUP_LIBYARA_NOT_AVAILABLE

#endif  /* !HAVE_YARA */
