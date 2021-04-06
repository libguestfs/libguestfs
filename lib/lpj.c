/* libguestfs
 * Copyright (C) 2012 Red Hat Inc.
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
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>

#include <pthread.h>

#include "guestfs.h"
#include "guestfs-internal.h"

/* Calculate host kernel loops_per_jiffy, so that this can be passed
 * to TCG guests (only) using the lpj= kernel parameter, which avoids
 * have to compute this at kernel boot time in a VM.
 *
 * Currently this is only available in the boot messages, but I have
 * posted a patch asking for this to be added to /proc/cpuinfo too.
 *
 * Notes:
 *
 * - We only try to calculate lpj once.
 *
 * - Trying to calculate lpj must not fail.  If the return value is
 *   <= 0, it is ignored by the caller.
 *
 * - KVM uses kvm-clock, but TCG uses some sort of jiffies source,
 *   which is why this is needed only for TCG appliances.
 *
 * (Suggested by Marcelo Tosatti)
 */

static pthread_mutex_t lpj_lock = PTHREAD_MUTEX_INITIALIZER;
static int lpj = 0;
static int read_lpj_from_dmesg (guestfs_h *g);
static int read_lpj_from_files (guestfs_h *g);
static int read_lpj_common (guestfs_h *g, const char *func, struct command *cmd);

int
guestfs_int_get_lpj (guestfs_h *g)
{
  int r;

  ACQUIRE_LOCK_FOR_CURRENT_SCOPE (&lpj_lock);
  if (lpj != 0)
    return lpj;

  /* Try reading lpj from these sources:
   * - /proc/cpuinfo [in future]
   * - dmesg
   * - files:
   *   + /var/log/dmesg
   *   + /var/log/boot.msg
   */
  r = read_lpj_from_dmesg (g);
  if (r > 0)
    return lpj = r;

  lpj = read_lpj_from_files (g);
  return lpj;
}

/* Grep the output, and print just the matching string "lpj=NNN". */
#define GREP_FLAGS "-Eoh"
#define GREP_REGEX "lpj=[[:digit:]]+"
#define GREP_CMD "grep " GREP_FLAGS " '" GREP_REGEX "'"

static int
read_lpj_from_dmesg (guestfs_h *g)
{
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);

  guestfs_int_cmd_add_string_unquoted (cmd, "dmesg | " GREP_CMD);

  return read_lpj_common (g, __func__, cmd);
}

#define FILE1 "/var/log/dmesg"
#define FILE2 "/var/log/boot.msg"

static int
read_lpj_from_files (guestfs_h *g)
{
  size_t files = 0;
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);

  guestfs_int_cmd_add_arg (cmd, "grep");
  guestfs_int_cmd_add_arg (cmd, GREP_FLAGS);
  guestfs_int_cmd_add_arg (cmd, GREP_REGEX);
  if (access (FILE1, R_OK) == 0) {
    guestfs_int_cmd_add_arg (cmd, FILE1);
    files++;
  }
  if (access (FILE2, R_OK) == 0) {
    guestfs_int_cmd_add_arg (cmd, FILE2);
    files++;
  }

  if (files > 0)
    return read_lpj_common (g, __func__, cmd);

  debug (g, "%s: no boot messages files are readable", __func__);
  return -1;
}

static void
read_all (guestfs_h *g, void *retv, const char *buf, size_t len)
{
  char **ret = retv;

  if (!*ret)
    *ret = safe_strndup (g, buf, len);
}

static int
read_lpj_common (guestfs_h *g, const char *func, struct command *cmd)
{
  int r;
  CLEANUP_FREE char *buf = NULL;

  guestfs_int_cmd_set_stdout_callback (cmd, read_all, &buf,
				       CMD_STDOUT_FLAG_WHOLE_BUFFER);
  r = guestfs_int_cmd_run (cmd);
  if (r == -1)
    return -1;
  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    char status_string[80];

    debug (g, "%s: %s", func,
           guestfs_int_exit_status_to_string (r, "external command",
					      status_string,
					      sizeof status_string));
    return -1;
  }

  if (buf == NULL) {
    debug (g, "%s: callback not called", func);
    return -1;
  }

  if (strlen (buf) < 4 || sscanf (&buf[4], "%d", &r) != 1) {
    debug (g, "%s: invalid buffer returned by grep: %s", func, buf);
    return -1;
  }

  debug (g, "%s: calculated lpj=%d", func, r);

  return r;
}
