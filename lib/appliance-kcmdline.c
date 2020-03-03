/* libguestfs
 * Copyright (C) 2009-2019 Red Hat Inc.
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
 * The appliance kernel command line.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>

#include "c-ctype.h"
#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal.h"

/**
 * Check that the $TERM environment variable is reasonable before
 * we pass it through to the appliance.
 */
#define VALID_TERM(term) \
  guestfs_int_string_is_valid ((term), 1, 16, \
                               VALID_FLAG_ALPHA|VALID_FLAG_DIGIT, "-_")

#if defined(__powerpc64__)
#define SERIAL_CONSOLE "console=hvc0 console=ttyS0"
#elif defined(__arm__) || defined(__aarch64__)
#define SERIAL_CONSOLE "console=ttyAMA0"
#elif defined(__s390x__)
#define SERIAL_CONSOLE "console=ttysclp0"
#else
#define SERIAL_CONSOLE "console=ttyS0"
#endif

#if defined(__aarch64__)
#define EARLYPRINTK "earlyprintk=pl011,0x9000000"
#endif

COMPILE_REGEXP (re_uuid, "UUID=([-0-9a-f]+)", 0)

static void
read_uuid (guestfs_h *g, void *retv, const char *line, size_t len)
{
  char **ret = retv;

  *ret = match1 (g, line, re_uuid);
}

/**
 * Given a disk image containing an extX filesystem, return the UUID.
 * The L<file(1)> command does the hard work.
 */
static char *
get_root_uuid (guestfs_h *g, const char *appliance)
{
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
  char *ret = NULL;
  int r;

  guestfs_int_cmd_add_arg (cmd, "file");
  guestfs_int_cmd_add_arg (cmd, "--");
  guestfs_int_cmd_add_arg (cmd, appliance);
  guestfs_int_cmd_set_stdout_callback (cmd, read_uuid, &ret, 0);
  r = guestfs_int_cmd_run (cmd);
  if (r == -1) {
    if (ret) free (ret);
    return NULL;
  }
  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    guestfs_int_external_command_failed (g, r, "file", NULL);
    if (ret) free (ret);
    return NULL;
  }

  return ret;
}

/**
 * Construct the Linux command line passed to the appliance.  This is
 * used by the C<direct> and C<libvirt> backends, and is simply
 * located in this file because it's a convenient place for this
 * common code.
 *
 * The C<appliance> parameter is the filename of the appliance
 * (could be NULL) from which we obtain the root UUID.
 *
 * The C<flags> parameter can contain the following flags logically
 * or'd together (or 0):
 *
 * =over 4
 *
 * =item C<APPLIANCE_COMMAND_LINE_IS_TCG>
 *
 * If we are launching a qemu TCG guest (ie. KVM is known to be
 * disabled or unavailable).  If you don't know, don't pass this flag.
 *
 * =back
 *
 * Note that this function returns a newly allocated buffer which must
 * be freed by the caller.
 */
char *
guestfs_int_appliance_command_line (guestfs_h *g,
                                    const char *appliance,
				    int flags)
{
  CLEANUP_FREE_STRINGSBUF DECLARE_STRINGSBUF (argv);
  char *term = getenv ("TERM");
  bool tcg = flags & APPLIANCE_COMMAND_LINE_IS_TCG;
  char *ret;

  /* We assemble the kernel command line by simply joining the final
   * list of strings with spaces.  This means (a) the strings are not
   * quoted (it's not clear if the kernel can handle quoting in any
   * case), and (b) we can append multiple parameters in a single
   * argument, as we must do for the g->append parameter.
   */

  /* Force kernel to panic if daemon exits. */
  guestfs_int_add_string (g, &argv, "panic=1");

#ifdef __arm__
  guestfs_int_add_sprintf (g, &argv, "mem=%dM", g->memsize);
#endif

#ifdef __i386__
  /* Workaround for RHBZ#857026. */
  guestfs_int_add_string (g, &argv, "noapic");
#endif

  /* Serial console. */
  guestfs_int_add_string (g, &argv, SERIAL_CONSOLE);

#ifdef EARLYPRINTK
  /* Get messages from early boot. */
  guestfs_int_add_string (g, &argv, EARLYPRINTK);
#endif

#ifdef __aarch64__
  guestfs_int_add_string (g, &argv, "ignore_loglevel");

  /* This option turns off the EFI RTC device.  QEMU VMs don't
   * currently provide EFI, and if the device is compiled in it
   * will try to call the EFI function GetTime unconditionally
   * (causing a call to NULL).  However this option requires a
   * non-upstream patch.
   */
  guestfs_int_add_string (g, &argv, "efi-rtc=noprobe");
#endif

  /* RHBZ#1404287 */
  guestfs_int_add_string (g, &argv, "edd=off");

  /* For slow systems (RHBZ#480319, RHBZ#1096579). */
  guestfs_int_add_string (g, &argv, "udevtimeout=6000");

  /* Same as above, for newer udevd. */
  guestfs_int_add_string (g, &argv, "udev.event-timeout=6000");

  /* Fix for RHBZ#502058. */
  guestfs_int_add_string (g, &argv, "no_timer_check");

  if (tcg) {
    const int lpj = guestfs_int_get_lpj (g);
    if (lpj > 0)
      guestfs_int_add_sprintf (g, &argv, "lpj=%d", lpj);
  }

  /* Display timestamp before kernel messages. */
  guestfs_int_add_string (g, &argv, "printk.time=1");

  /* Saves us about 5 MB of RAM. */
  guestfs_int_add_string (g, &argv, "cgroup_disable=memory");

  /* Disable USB, only saves about 1ms. */
  guestfs_int_add_string (g, &argv, "usbcore.nousb");

  /* Disable crypto tests, saves 28ms. */
  guestfs_int_add_string (g, &argv, "cryptomgr.notests");

  /* Don't synch TSCs when using SMP.  Saves 21ms for each secondary vCPU. */
  guestfs_int_add_string (g, &argv, "tsc=reliable");

  /* Don't scan all 8250 UARTS. */
  guestfs_int_add_string (g, &argv, "8250.nr_uarts=1");

  /* Tell supermin about the appliance device. */
  if (appliance) {
    CLEANUP_FREE char *uuid = get_root_uuid (g, appliance);
    if (!uuid)
      return NULL;
    guestfs_int_add_sprintf (g, &argv, "root=UUID=%s", uuid);
  }

  /* SELinux - deprecated setting, never worked and should not be enabled. */
  if (g->selinux)
    guestfs_int_add_string (g, &argv, "selinux=1 enforcing=0");
  else
    guestfs_int_add_string (g, &argv, "selinux=0");

  /* Quiet/verbose. */
  if (g->verbose)
    guestfs_int_add_string (g, &argv, "guestfs_verbose=1");
  else
    guestfs_int_add_string (g, &argv, "quiet");

  /* Network. */
  if (g->enable_network)
    guestfs_int_add_string (g, &argv, "guestfs_network=1");

  /* TERM environment variable. */
  if (term && VALID_TERM (term))
    guestfs_int_add_sprintf (g, &argv, "TERM=%s", term);
  else
    guestfs_int_add_string (g, &argv, "TERM=linux");

  /* Handle identifier. */
  if (STRNEQ (g->identifier, ""))
    guestfs_int_add_sprintf (g, &argv, "guestfs_identifier=%s", g->identifier);

  /* Append extra arguments. */
  if (g->append)
    guestfs_int_add_string (g, &argv, g->append);

  guestfs_int_end_stringsbuf (g, &argv);

  /* Caller frees. */
  ret = guestfs_int_join_strings (" ", argv.argv);
  if (ret == NULL)
    g->abort_cb ();
  return ret;
}
