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
#include <stdint.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include "glthread/lock.h"

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
 * - We only try to calculate lpj once.
 * - Trying to calculate lpj must not fail.  If the return value is
 *   <= 0, it is ignored by the caller.
 *
 * (Suggested by Marcelo Tosatti)
 */

gl_lock_define_initialized (static, lpj_lock);
static int lpj = 0;
static int read_lpj_from_var_log_dmesg (guestfs_h *g);
static int read_lpj_from_dmesg (guestfs_h *g);
static int read_lpj_common (guestfs_h *g, const char *func, const char *command);

int
guestfs___get_lpj (guestfs_h *g)
{
  int r;

  gl_lock_lock (lpj_lock);
  if (lpj != 0)
    goto out;

  /* Try reading lpj from these sources:
   * - /proc/cpuinfo [in future]
   * - dmesg
   * - /var/log/dmesg
   */
  r = read_lpj_from_dmesg (g);
  if (r > 0) {
    lpj = r;
    goto out;
  }
  lpj = read_lpj_from_var_log_dmesg (g);

 out:
  gl_lock_unlock (lpj_lock);
  return lpj;
}

static int
read_lpj_from_dmesg (guestfs_h *g)
{
  return read_lpj_common (g, __func__,
                          "dmesg | grep -Eo 'lpj=[[:digit:]]+'");
}

static int
read_lpj_from_var_log_dmesg (guestfs_h *g)
{
  return read_lpj_common (g, __func__,
                          "grep -Eo 'lpj=[[:digit:]]+' /var/log/dmesg");
}

static void
read_all (guestfs_h *g, void *retv, const char *buf, size_t len)
{
  char **ret = retv;

  *ret = safe_strndup (g, buf, len);
}

static int
read_lpj_common (guestfs_h *g, const char *func, const char *command)
{
  struct command *cmd;
  int r;
  char *buf = NULL;

  cmd = guestfs___new_command (g);
  guestfs___cmd_add_string_unquoted (cmd, command);
  guestfs___cmd_set_stdout_callback (cmd, read_all, &buf,
                                     CMD_STDOUT_FLAG_WHOLE_BUFFER);
  r = guestfs___cmd_run (cmd);
  guestfs___cmd_close (cmd);

  if (r == -1 || !WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    debug (g, "%s: command failed with code %d: %s", func, r, command);
    free (buf);
    return -1;
  }

  if (buf == NULL) {
    debug (g, "%s: callback not called", func);
    return -1;
  }

  if (strlen (buf) < 4 || sscanf (&buf[4], "%d", &r) != 1) {
    debug (g, "%s: invalid buffer returned by grep: %s", func, buf);
    free (buf);
    return -1;
  }

  free (buf);

  debug (g, "%s: calculated lpj=%d", func, r);

  return r;
}
