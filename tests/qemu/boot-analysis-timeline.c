/* libguestfs
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <string.h>
#include <unistd.h>
#include <error.h>
#include <errno.h>
#include <assert.h>

#include <pcre.h>

#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal-frontend.h"

#include "boot-analysis.h"

COMPILE_REGEXP(re_initcall_calling_module,
               "calling  ([_A-Za-z0-9]+)\\+.*\\[([_A-Za-z0-9]+)]", 0)
COMPILE_REGEXP(re_initcall_calling,
               "calling  ([_A-Za-z0-9]+)\\+", 0)

static void construct_initcall_timeline (void);

/* "supermin: internal insmod xx.ko" -> "insmod xx.ko" */
static char *
translate_supermin_insmod_message (const char *message)
{
  char *ret;

  assert (STRPREFIX (message, "supermin: internal "));

  ret = strdup (message + strlen ("supermin: internal "));
  if (ret == NULL)
    error (EXIT_FAILURE, errno, "strdup");
  return ret;
}

/* Analyze significant events from the events array, to form a
 * timeline of activities.
 */
void
construct_timeline (void)
{
  size_t i, j, k;
  struct pass_data *data;
  struct activity *activity;

  for (i = 0; i < NR_TEST_PASSES; ++i) {
    data = &pass_data[i];

    /* Find an activity, by matching an event with the condition
     * `begin_cond' through to the second event `end_cond'.  Create an
     * activity object in the timeline from the result.
     */
#define FIND(name, flags, begin_cond, end_cond)                         \
    do {                                                                \
      activity = NULL;                                                  \
      for (j = 0; j < data->nr_events; ++j) {                           \
        if (begin_cond) {                                               \
          for (k = j+1; k < data->nr_events; ++k) {                     \
            if (end_cond) {                                             \
              if (i == 0)                                               \
                activity = add_activity (name, flags);                  \
              else                                                      \
                activity = find_activity (name);                        \
              break;                                                    \
            }                                                           \
          }                                                             \
          break;                                                        \
        }                                                               \
      }                                                                 \
      if (activity) {                                                   \
        activity->start_event[i] = j;                                   \
        activity->end_event[i] = k;                                     \
      }                                                                 \
      else                                                              \
        error (EXIT_FAILURE, 0, "could not find activity '%s' in pass '%zu'", \
               name, i);                                                \
    } while (0)

    /* Same as FIND() macro, but if no matching events are found,
     * ignore it.
     */
#define FIND_OPTIONAL(name, flags, begin_cond, end_cond)                \
    do {                                                                \
      activity = NULL;                                                  \
      for (j = 0; j < data->nr_events; ++j) {                           \
        if (begin_cond) {                                               \
          for (k = j+1; k < data->nr_events; ++k) {                     \
            if (end_cond) {                                             \
              if (i == 0)                                               \
                activity = add_activity (name, flags);                  \
              else                                                      \
                activity = find_activity (name);                        \
              break;                                                    \
            }                                                           \
          }                                                             \
          break;                                                        \
        }                                                               \
      }                                                                 \
      if (activity) {                                                   \
        activity->start_event[i] = j;                                   \
        activity->end_event[i] = k;                                     \
      }                                                                 \
    } while (0)

    /* Find multiple entries, where we check for:
     *   next_cond
     *   next_cond
     *   next_cond
     *   end_cond
     */
#define FIND_MULTIPLE(debug_name, flags, next_cond, end_cond, translate_message) \
    do {                                                                \
      activity = NULL;                                                  \
      for (j = 0; j < data->nr_events; ++j) {                           \
        if (next_cond) {                                                \
          CLEANUP_FREE char *message = translate_message (data->events[j].message); \
          if (activity)                                                 \
            activity->end_event[i] = j;                                 \
          if (i == 0)                                                   \
            activity = add_activity (message, flags);                   \
          else                                                          \
            activity = find_activity (message);                         \
          activity->start_event[i] = j;                                 \
        }                                                               \
        else if (end_cond)                                              \
          break;                                                        \
      }                                                                 \
      if (j < data->nr_events && activity)                              \
        activity->end_event[i] = j;                                     \
      else                                                              \
        error (EXIT_FAILURE, 0, "could not find activity '%s' in pass '%zu'", \
               debug_name, i);                                          \
    } while (0)

    /* Add one activity which is going to cover the whole process
     * from launch to close.  The launch event is always event 0.
     * NB: This activity must be called "run" (see below).
     */
    FIND ("run", LONG_ACTIVITY,
          j == 0, data->events[k].source == GUESTFS_EVENT_CLOSE);

    /* Find where we invoke supermin --build.  This should be a null
     * operation, but it still takes time to run the external command.
     */
    FIND ("supermin:build", 0,
          data->events[j].source == GUESTFS_EVENT_LIBRARY &&
          strstr (data->events[j].message,
                  "begin building supermin appliance"),
          data->events[k].source == GUESTFS_EVENT_LIBRARY &&
          strstr (data->events[k].message,
                  "finished building supermin appliance"));

    /* Find where we invoke qemu to test features. */
    FIND_OPTIONAL ("qemu:feature-detect", 0,
                   data->events[j].source == GUESTFS_EVENT_LIBRARY &&
                   strstr (data->events[j].message,
                           "begin testing qemu features"),
                   data->events[k].source == GUESTFS_EVENT_LIBRARY &&
                   strstr (data->events[k].message,
                           "finished testing qemu features"));

    /* Find where we run qemu. */
    FIND_OPTIONAL ("qemu", LONG_ACTIVITY,
                   data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
                   strstr (data->events[j].message, "-nodefconfig"),
                   data->events[k].source == GUESTFS_EVENT_CLOSE);

    /* For the libvirt backend, connecting to libvirt, getting
     * capabilities, parsing capabilities etc.
     */
    FIND_OPTIONAL ("libvirt:connect", 0,
                   data->events[j].source == GUESTFS_EVENT_LIBRARY &&
                   strstr (data->events[j].message, "connect to libvirt"),
                   data->events[k].source == GUESTFS_EVENT_LIBRARY &&
                   strstr (data->events[k].message, "successfully opened libvirt handle"));
    FIND_OPTIONAL ("libvirt:get-libvirt-capabilities", 0,
                   data->events[j].source == GUESTFS_EVENT_LIBRARY &&
                   strstr (data->events[j].message, "get libvirt capabilities"),
                   data->events[k].source == GUESTFS_EVENT_LIBRARY &&
                   strstr (data->events[k].message, "parsing capabilities XML"));

    FIND_OPTIONAL ("libguestfs:parse-libvirt-capabilities", 0,
                   data->events[j].source == GUESTFS_EVENT_LIBRARY &&
                   strstr (data->events[j].message, "parsing capabilities XML"),
                   data->events[k].source == GUESTFS_EVENT_LIBRARY &&
                   strstr (data->events[k].message, "get_backend_setting"));

    FIND_OPTIONAL ("libguestfs:create-libvirt-xml", 0,
                   data->events[j].source == GUESTFS_EVENT_LIBRARY &&
                   strstr (data->events[j].message, "create libvirt XML"),
                   data->events[k].source == GUESTFS_EVENT_LIBRARY &&
                   strstr (data->events[k].message, "libvirt XML:"));

#if defined(__aarch64__)
#define FIRST_KERNEL_MESSAGE "Booting Linux on physical CPU"
#define FIRST_FIRMWARE_MESSAGE "UEFI firmware starting"
#else
#define SGABIOS_STRING "\033[1;256r\033[256;256H\033[6n"
#define FIRST_KERNEL_MESSAGE "Probing EDD"
#define FIRST_FIRMWARE_MESSAGE SGABIOS_STRING
#endif

    /* For the libvirt backend, find the overhead of libvirt. */
    FIND_OPTIONAL ("libvirt:overhead", 0,
                   data->events[j].source == GUESTFS_EVENT_LIBRARY &&
                   strstr (data->events[j].message, "launch libvirt guest"),
                   data->events[k].source == GUESTFS_EVENT_APPLIANCE &&
                   strstr (data->events[k].message, FIRST_FIRMWARE_MESSAGE));

    /* From starting qemu up to entering the BIOS is the qemu overhead. */
    FIND_OPTIONAL ("qemu:overhead", 0,
                   data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
                   strstr (data->events[j].message, "-nodefconfig"),
                   data->events[k].source == GUESTFS_EVENT_APPLIANCE &&
                   strstr (data->events[k].message, FIRST_FIRMWARE_MESSAGE));

    /* From entering the BIOS to starting the kernel is the BIOS overhead. */
    FIND_OPTIONAL ("bios:overhead", 0,
          data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[j].message, FIRST_FIRMWARE_MESSAGE),
          data->events[k].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[k].message, FIRST_KERNEL_MESSAGE));

#if defined(__i386__) || defined(__x86_64__)
    /* SGABIOS (option ROM). */
    FIND_OPTIONAL ("sgabios", 0,
          data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[j].message, SGABIOS_STRING),
          data->events[k].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[k].message, "SeaBIOS (version"));
#endif

#if defined(__i386__) || defined(__x86_64__)
    /* SeaBIOS. */
    FIND ("seabios", 0,
          data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[j].message, "SeaBIOS (version"),
          data->events[k].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[k].message, FIRST_KERNEL_MESSAGE));
#endif

#if defined(__i386__) || defined(__x86_64__)
    /* SeaBIOS - only available when using debug messages. */
    FIND_OPTIONAL ("seabios:pci-probe", 0,
          data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[j].message, "Searching bootorder for: /pci@"),
          data->events[k].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[k].message, "Scan for option roms"));
#endif

    /* Find where we run the guest kernel. */
    FIND ("kernel", LONG_ACTIVITY,
          data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[j].message, FIRST_KERNEL_MESSAGE),
          data->events[k].source == GUESTFS_EVENT_CLOSE);

    /* Kernel startup to userspace. */
    FIND ("kernel:overhead", 0,
          data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[j].message, FIRST_KERNEL_MESSAGE),
          data->events[k].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[k].message, "supermin:") &&
          strstr (data->events[k].message, "starting up"));

    /* The time taken to get into start_kernel function. */
    FIND ("kernel:entry", 0,
          data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[j].message, FIRST_KERNEL_MESSAGE),
          data->events[k].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[k].message, "Linux version"));

#if defined(__i386__) || defined(__x86_64__)
    /* Alternatives patching instructions (XXX not very accurate we
     * really need some debug messages inserted into the code).
     */
    FIND ("kernel:alternatives", 0,
          data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[j].message, "Last level dTLB entries"),
          data->events[k].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[k].message, "Freeing SMP alternatives"));
#endif

    /* ftrace patching instructions. */
    FIND ("kernel:ftrace", 0,
          data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[j].message, "ftrace: allocating"),
          1);

    /* All initcall functions, before we enter userspace. */
    FIND ("kernel:initcalls-before-userspace", 0,
          data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[j].message, "calling  "),
          data->events[k].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[k].message, "Freeing unused kernel memory"));

    /* Find where we run supermin mini-initrd. */
    FIND ("supermin:mini-initrd", 0,
          data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[j].message, "supermin:") &&
          strstr (data->events[j].message, "starting up"),
          data->events[k].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[k].message, "supermin: chroot"));

    /* Loading kernel modules from supermin initrd. */
    FIND_MULTIPLE
      ("supermin insmod", 0,
       data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
       strstr (data->events[j].message, "supermin: internal insmod"),
       data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
       strstr (data->events[j].message, "supermin: picked"),
       translate_supermin_insmod_message);

    /* Find where we run the /init script. */
    FIND ("/init", 0,
          data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[j].message, "supermin: chroot"),
          data->events[k].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[k].message, "guestfsd --verbose"));

    /* Everything from the chroot to the first echo in the /init
     * script counts as bash overhead.
     */
    FIND ("bash:overhead", 0,
          data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[j].message, "supermin: chroot"),
          data->events[k].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[k].message, "Starting /init script"));

    /* /init: Mount special filesystems. */
    FIND ("/init:mount-special", 0,
          data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[j].message, "*guestfs_boot_analysis=1*"),
          data->events[k].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[k].message, "kmod static-nodes"));

    /* /init: Run kmod static-nodes */
    FIND ("/init:kmod-static-nodes", 0,
          data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[j].message, "kmod static-nodes"),
          data->events[k].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[k].message, "systemd-tmpfiles"));

    /* /init: systemd-tmpfiles. */
    FIND ("/init:systemd-tmpfiles", 0,
          data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[j].message, "systemd-tmpfiles"),
          data->events[k].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[k].message, "udev"));

    /* /init: start udevd. */
    FIND ("/init:udev-overhead", 0,
          data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[j].message, "udevd --daemon"),
          data->events[k].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[k].message, "nullglob"));

    /* /init: set up network. */
    FIND ("/init:network-overhead", 0,
          data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[j].message, "+ ip addr"),
          data->events[k].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[k].message, "+ test"));

    /* /init: probe MD arrays. */
    FIND ("/init:md-probe", 0,
          data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[j].message, "+ mdadm"),
          data->events[k].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[k].message, "+ modprobe dm_mod"));

    /* /init: probe DM/LVM. */
    FIND ("/init:lvm-probe", 0,
          data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[j].message, "+ modprobe dm_mod"),
          data->events[k].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[k].message, "+ ldmtool"));

    /* /init: probe Windows dynamic disks. */
    FIND ("/init:windows-dynamic-disks-probe", 0,
          data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[j].message, "+ ldmtool"),
          data->events[k].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[k].message, "+ test"));

    /* Find where we run guestfsd. */
    FIND ("guestfsd", 0,
          data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[j].message, "guestfsd --verbose"),
          data->events[k].source == GUESTFS_EVENT_APPLIANCE &&
          strstr (data->events[k].message, "fsync /dev/sda"));

    /* Shutdown process. */
    FIND ("shutdown", 0,
          data->events[j].source == GUESTFS_EVENT_TRACE &&
          STREQ (data->events[j].message, "close"),
          data->events[k].source == GUESTFS_EVENT_CLOSE);
  }

  construct_initcall_timeline ();
}

/* Handling of initcall is so peculiar that we hide it in a separate
 * function from the rest.
 */
static void
construct_initcall_timeline (void)
{
  size_t i, j, k;
  struct pass_data *data;
  struct activity *activity;

  for (i = 0; i < NR_TEST_PASSES; ++i) {
    data = &pass_data[i];

    /* Each kernel initcall is bracketed by:
     *
     * calling  ehci_hcd_init+0x0/0xc1 @ 1"
     * initcall ehci_hcd_init+0x0/0xc1 returned 0 after 420 usecs"
     *
     * For initcall functions in modules:
     *
     * calling  virtio_mmio_init+0x0/0x1000 [virtio_mmio] @ 1"
     * initcall virtio_mmio_init+0x0/0x1000 [virtio_mmio] returned 0 after 14 usecs"
     *
     * Initcall functions can be nested, and do not have unique names.
     */
    for (j = 0; j < data->nr_events; ++j) {
      int vec[30], r;
      const char *message = data->events[j].message;

      if (data->events[j].source == GUESTFS_EVENT_APPLIANCE &&
          ((r = pcre_exec (re_initcall_calling_module, NULL,
                           message, strlen (message),
                           0, 0, vec, sizeof vec / sizeof vec[0])) >= 1 ||
           (r = pcre_exec (re_initcall_calling, NULL,
                           message, strlen (message),
                           0, 0, vec, sizeof vec / sizeof vec[0])) >= 1)) {

        CLEANUP_FREE char *fn_name = NULL, *module_name = NULL;
        if (r >= 2) /* because pcre_exec returns 1 + number of captures */
          fn_name = strndup (message + vec[2], vec[3]-vec[2]);
        if (r >= 3)
          module_name = strndup (message + vec[4], vec[5]-vec[4]);

        CLEANUP_FREE char *fullname;
        if (asprintf (&fullname, "%s.%s",
                      module_name ? module_name : "kernel", fn_name) == -1)
          error (EXIT_FAILURE, errno, "asprintf");

        CLEANUP_FREE char *initcall_match;
        if (asprintf (&initcall_match, "initcall %s", fn_name) == -1)
          error (EXIT_FAILURE, errno, "asprintf");

        /* Get a unique name for this activity.  Unfortunately
         * kernel initcall function names are not unique!
         */
        CLEANUP_FREE char *activity_name;
        if (asprintf (&activity_name, "initcall %s", fullname) == -1)
          error (EXIT_FAILURE, errno, "asprintf");

        if (i == 0) {
          int n = 1;
          while (activity_exists (activity_name)) {
            free (activity_name);
            if (asprintf (&activity_name, "initcall %s:%d", fullname, n) == -1)
              error (EXIT_FAILURE, errno, "asprintf");
            n++;
          }
        }
        else {
          int n = 1;
          while (!activity_exists_with_no_data (activity_name, i)) {
            free (activity_name);
            if (asprintf (&activity_name, "initcall %s:%d", fullname, n) == -1)
              error (EXIT_FAILURE, errno, "asprintf");
            n++;
          }
        }

        /* Find the matching end event.  It might be some time later,
         * since it appears initcalls can be nested.
         */
        for (k = j+1; k < data->nr_events; ++k) {
          if (data->events[k].source == GUESTFS_EVENT_APPLIANCE &&
              strstr (data->events[k].message, initcall_match)) {
            if (i == 0)
              activity = add_activity (activity_name, 0);
            else
              activity = find_activity (activity_name);
            activity->start_event[i] = j;
            activity->end_event[i] = k;
            break;
          }
        }
      }
    }
  }
}
