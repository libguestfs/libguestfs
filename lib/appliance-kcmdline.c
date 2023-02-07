/* libguestfs
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

/**
 * The appliance kernel command line.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <libintl.h>
#include <sys/types.h>

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

/**
 * Given a disk image containing an extX filesystem, return the UUID.
 */
static char *
get_root_uuid_with_file (guestfs_h *g, const char *appliance)
{
  unsigned char magic[4], uuid[16];
  char *ret;
  int fd;

  fd = open (appliance, O_RDONLY|O_CLOEXEC);
  if (fd == -1) {
    perrorf (g, _("open: %s"), appliance);
    return NULL;
  }
  if (read (fd, magic, 4) != 4 || !strncmp ((char *) magic, "QFI\xfb", 4)) {
    /* No point looking for extfs signature in QCOW2 directly. */
    return NULL;
  }
  if (lseek (fd, 0x438, SEEK_SET) != 0x438) {
  magic_error:
    error (g, _("%s: cannot read extfs magic in superblock"), appliance);
    close (fd);
    return NULL;
  }
  if (read (fd, magic, 2) != 2)
    goto magic_error;
  if (magic[0] != 0x53 || magic[1] != 0xEF) {
    error (g, _("%s: appliance is not an extfs filesystem"), appliance);
    close (fd);
    return NULL;
  }
  if (lseek (fd, 0x468, SEEK_SET) != 0x468) {
  super_error:
    error (g, _("%s: cannot read UUID in superblock"), appliance);
    close (fd);
    return NULL;
  }
  if (read (fd, uuid, 16) != 16)
    goto super_error;
  close (fd);

  /* The UUID is a binary blob, but we must return it as a printable
   * string.  The caller frees this.
   */
  ret = safe_asprintf (g,
                       "%02x%02x%02x%02x" "-"
                       "%02x%02x" "-"
                       "%02x%02x" "-"
                       "%02x%02x" "-"
                       "%02x%02x%02x%02x%02x%02x",
                       uuid[0], uuid[1], uuid[2], uuid[3],
                       uuid[4], uuid[5],
                       uuid[6], uuid[7],
                       uuid[8], uuid[9],
                       uuid[10], uuid[11], uuid[12], uuid[13],
                         uuid[14], uuid[15]);
  return ret;
}

/**
 * Read the first 256k bytes of the in_file with L<qemu-img(1)>
 * command and write them into the out_file. That may be useful to get
 * UUID of the QCOW2 disk image with C<get_root_uuid_with_file>.
 *
 * The function returns zero if successful, otherwise -1.
 */
static int
run_qemu_img_dd (guestfs_h *g, const char *in_file, char *out_file)
{
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
  int r;

  guestfs_int_cmd_add_arg (cmd, "qemu-img");
  guestfs_int_cmd_add_arg (cmd, "dd");
  guestfs_int_cmd_add_arg_format (cmd, "if=%s", in_file);
  guestfs_int_cmd_add_arg_format (cmd, "of=%s", out_file);
  guestfs_int_cmd_add_arg (cmd, "bs=256k");
  guestfs_int_cmd_add_arg (cmd, "count=1");

  r = guestfs_int_cmd_run (cmd);
  if (r == -1) {
    error (g, "Failed to run qemu-img");
    return -1;
  }
  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    guestfs_int_external_command_failed (g, r, "qemu-img dd", NULL);
    return -1;
  }

  return 0;
}

/**
 * Get the UUID from the appliance disk image.
 */
static char *
get_root_uuid (guestfs_h *g, const char *appliance)
{
  char *uuid = NULL;
  CLEANUP_UNLINK_FREE char *tmpfile = NULL;

  uuid = get_root_uuid_with_file (g, appliance);
  if (uuid) {
      return uuid;
  }

  tmpfile = guestfs_int_make_temp_path (g, "root", "raw");
  if (!tmpfile)
    return NULL;

  if (run_qemu_img_dd (g, appliance, tmpfile) == -1)
    return NULL;

  uuid = get_root_uuid_with_file (g, tmpfile);
  if (!uuid) {
    error (g, "Failed to get the appliance UUID");
  }

  return uuid;
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
