/* virt-p2v
 * Copyright (C) 2009-2014 Red Hat Inc.
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
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <fcntl.h>
#include <inttypes.h>
#include <unistd.h>
#include <time.h>
#include <errno.h>
#include <locale.h>
#include <assert.h>
#include <libintl.h>
#include <sys/types.h>
#include <sys/wait.h>

#include <glib.h>

#include "miniexpect.h"
#include "p2v.h"

/* Data per NBD connection / physical disk. */
struct data_conn {
  mexp_h *h;                /* miniexpect handle to ssh */
  pid_t nbd_pid;            /* qemu pid */
  int nbd_local_port;       /* local NBD port on physical machine */
  int nbd_remote_port;      /* remote NBD port on conversion server */
};

static pid_t start_qemu_nbd (int nbd_local_port, const char *device);
static void cleanup_data_conns (struct data_conn *data_conns, size_t nr);
static char *generate_libvirt_xml (struct config *, struct data_conn *);
static void debug_parameters (struct config *);

static char *conversion_error;

static void set_conversion_error (const char *fs, ...)
  __attribute__((format(printf,1,2)));

static void
set_conversion_error (const char *fs, ...)
{
  va_list args;
  char *msg;
  int len;

  va_start (args, fs);
  len = vasprintf (&msg, fs, args);
  va_end (args);

  if (len < 0) {
    perror ("vasprintf");
    fprintf (stderr, "original error format string: %s\n", fs);
    exit (EXIT_FAILURE);
  }

  free (conversion_error);
  conversion_error = msg;
}

const char *
get_conversion_error (void)
{
  return conversion_error;
}

#pragma GCC diagnostic ignored "-Wsuggest-attribute=noreturn"
int
start_conversion (struct config *config,
                  void (*notify_ui) (int type, const char *data))
{
  int ret = -1;
  size_t i, len;
  size_t nr_disks = guestfs___count_strings (config->disks);
  struct data_conn data_conns[nr_disks];
  CLEANUP_FREE char *remote_dir = NULL, *libvirt_xml = NULL;
  time_t now;
  struct tm tm;
  mexp_h *control_h = NULL;

  debug_parameters (config);

  for (i = 0; config->disks[i] != NULL; ++i) {
    data_conns[i].h = NULL;
    data_conns[i].nbd_pid = 0;
    data_conns[i].nbd_local_port = -1;
    data_conns[i].nbd_remote_port = -1;
  }

  /* Start the data connections and qemu-nbd processes, one per disk. */
  for (i = 0; config->disks[i] != NULL; ++i) {
    CLEANUP_FREE char *device = NULL;

    if (notify_ui) {
      CLEANUP_FREE char *msg;
      if (asprintf (&msg,
                    _("Opening data connection for %s ..."),
                    config->disks[i]) == -1) {
        perror ("asprintf");
        exit (EXIT_FAILURE);
      }
      notify_ui (NOTIFY_STATUS, msg);
    }

    data_conns[i].h = open_data_connection (config,
                                            &data_conns[i].nbd_local_port,
                                            &data_conns[i].nbd_remote_port);
    if (data_conns[i].h == NULL) {
      const char *err = get_ssh_error ();

      set_conversion_error ("could not open data connection over SSH to the conversion server: %s", err);
      goto out;
    }

    if (asprintf (&device, "/dev/%s", config->disks[i]) == -1) {
      perror ("asprintf");
      cleanup_data_conns (data_conns, nr_disks);
      exit (EXIT_FAILURE);
    }

    /* Start qemu-nbd listening on the given port number. */
    data_conns[i].nbd_pid =
      start_qemu_nbd (data_conns[i].nbd_local_port, device);
    if (data_conns[i].nbd_pid == 0)
      goto out;

#if DEBUG_STDERR
    fprintf (stderr,
             "%s: data connection for %s: SSH remote port %d, local port %d\n",
             program_name, device,
             data_conns[i].nbd_remote_port, data_conns[i].nbd_local_port);
#endif
  }

  /* Create a remote directory name which will be used for libvirt
   * XML, log files and other stuff.  We don't delete this directory
   * after the run because (a) it's useful for debugging and (b) it
   * only contains small files.
   *
   * NB: This path MUST NOT require shell quoting.
   */
  time (&now);
  gmtime_r (&now, &tm);
  if (asprintf (&remote_dir,
                "/tmp/virt-p2v-%04d%02d%02d-XXXXXXXX",
                tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday) == -1) {
    perror ("asprintf");
    cleanup_data_conns (data_conns, nr_disks);
    exit (EXIT_FAILURE);
  }
  len = strlen (remote_dir);
  guestfs___random_string (&remote_dir[len-8], 8);
  if (notify_ui)
    notify_ui (NOTIFY_LOG_DIR, remote_dir);

  /* Generate the libvirt XML. */
  libvirt_xml = generate_libvirt_xml (config, data_conns);
  if (libvirt_xml == NULL)
    goto out;

#if DEBUG_STDERR
  fprintf (stderr, "%s: libvirt XML:\n%s", program_name, libvirt_xml);
#endif

  /* Open the control connection and start conversion */
  if (notify_ui)
    notify_ui (NOTIFY_STATUS, _("Setting up the control connection ..."));

  control_h = start_remote_connection (config, remote_dir, libvirt_xml);
  if (control_h == NULL) {
    const char *err = get_ssh_error ();

    set_conversion_error ("could not open control connection over SSH to the conversion server: %s", err);
    goto out;
  }

  /* Do the conversion.  This runs until virt-v2v exits. */
  if (notify_ui)
    notify_ui (NOTIFY_STATUS, _("Doing conversion ..."));

  if (mexp_printf (control_h,
                   "( "
                   "%s"
                   "virt-v2v"
                   "%s"
                   " -i libvirtxml"
                   " -o local -os /tmp" /* XXX */
                   " --root first"
                   " %s/guest.xml"
                   " </dev/null" /* stdin */
                   " 2>&1"       /* output */
                   " ;"
                   " echo $? > %s/status"
                   " )"
                   " | tee %s/virt-v2v-conversion-log.txt"
                   " ;"
                   " exit"
                   "\n",
                   config->sudo ? "sudo " : "",
                   config->verbose ? " -v -x" : "",
                   remote_dir,
                   remote_dir,
                   remote_dir) == -1) {
    set_conversion_error ("mexp_printf: virt-v2v command: %m");
    goto out;
  }

  /* Read output from the virt-v2v process and echo it through the
   * notify function, until virt-v2v closes the connection.
   */
  for (;;) {
    char buf[257];
    ssize_t r;

    r = read (control_h->fd, buf, sizeof buf - 1);
    if (r == -1) {
      /* See comment about this in miniexpect.c. */
      if (errno == EIO)
        break;                  /* EOF */
      set_conversion_error ("read: %m");
      goto out;
    }
    if (r == 0)
      break;                    /* EOF */
    buf[r] = '\0';
    if (notify_ui)
      notify_ui (NOTIFY_REMOTE_MESSAGE, buf);
  }

  if (notify_ui)
    notify_ui (NOTIFY_STATUS, _("Control connection closed by remote."));

  ret = 0;
 out:
  if (control_h)
    mexp_close (control_h);
  cleanup_data_conns (data_conns, nr_disks);
  return ret;
}

/* Note: returns process ID (> 0) or 0 if there is an error. */
static pid_t
start_qemu_nbd (int port, const char *device)
{
  pid_t pid;
  char port_str[64];

  snprintf (port_str, sizeof port_str, "%d", port);

  pid = fork ();
  if (pid == -1) {
    set_conversion_error ("fork: %m");
    return 0;
  }

  if (pid == 0) {               /* Child. */
    close (0);
    open ("/dev/null", O_RDONLY);

    execlp ("qemu-nbd",
            "qemu-nbd",
            "-r",               /* readonly (vital!) */
            "-p", port_str,     /* listening port */
            "-t",               /* persistent */
            "-f", "raw",        /* force raw format */
            "-b", "localhost",  /* listen only on loopback interface */
            "--cache=unsafe",   /* use unsafe caching for speed */
            device,             /* a device like /dev/sda */
            NULL);
    perror ("qemu-nbd");
    _exit (EXIT_FAILURE);
  }

  /* Parent. */
  return pid;
}

static void
cleanup_data_conns (struct data_conn *data_conns, size_t nr)
{
  size_t i;

  for (i = 0; i < nr; ++i) {
    if (data_conns[i].h != NULL) {
      /* Because there is no SSH prompt (ssh -N), the only way to kill
       * these ssh connections is to send a signal.  Just closing the
       * pipe doesn't do anything.
       */
      kill (data_conns[i].h->pid, SIGHUP);
      mexp_close (data_conns[i].h);
    }

    if (data_conns[i].nbd_pid > 0) {
      /* Kill qemu-nbd process and clean up. */
      kill (data_conns[i].nbd_pid, SIGTERM);
      waitpid (data_conns[i].nbd_pid, NULL, 0);
    }
  }
}

/* Write the libvirt XML for this physical machine.  Note this is not
 * actually input for libvirt.  It's input for virt-v2v on the
 * conversion server, and virt-v2v will (if necessary) generate the
 * final libvirt XML.
 */
static char *
generate_libvirt_xml (struct config *config, struct data_conn *data_conns)
{
  uint64_t memkb;
  FILE *fp;
  char *ret = NULL;
  size_t len = 0;
  size_t i;

  fp = open_memstream (&ret, &len);
  if (fp == NULL) {
    set_conversion_error ("open_memstream: %m");
    return NULL;
  }

  memkb = config->memory / 1024;

  fprintf (fp,
           "<!--\n"
           "  NOTE!\n"
           "\n"
           "  This libvirt XML is generated by the virt-p2v front end, in\n"
           "  order to communicate with the backend virt-v2v process running\n"
           "  on the conversion server.  It is a minimal description of the\n"
           "  physical machine.  If the target of the conversion is libvirt,\n"
           "  then virt-v2v will generate the real target libvirt XML, which\n"
           "  has only a little to do with the XML in this file.\n"
           "\n"
           "  For the code that generates this XML, see %s in the virt-p2v\n"
           "  sources (in the libguestfs package).\n"
           "-->\n"
           "\n",
           __FILE__);

  /* XXX quoting needs to be improved here XXX */
  fprintf (fp,
           "<domain>\n"
           "  <name>%s</name>\n"
           "  <memory unit='KiB'>%" PRIu64 "</memory>\n"
           "  <currentMemory unit='KiB'>%" PRIu64 "</currentMemory>\n"
           "  <vcpu>%d</vcpu>\n"
           "  <os>\n"
           "    <type arch='" host_cpu "'>hvm</type>\n"
           "  </os>\n"
           "  <features>%s%s%s</features>\n"
           "  <devices>\n",
           config->guestname,
           memkb, memkb,
           config->vcpus,
           config->flags & FLAG_ACPI ? "<acpi/>" : "",
           config->flags & FLAG_APIC ? "<apic/>" : "",
           config->flags & FLAG_PAE  ? "<pae/>" : "");

  for (i = 0; config->disks[i] != NULL; ++i) {
    fprintf (fp,
             "    <disk type='network' device='disk'>\n"
             "      <driver name='qemu' type='raw'/>\n"
             "      <source protocol='nbd'>\n"
             "        <host name='localhost' port='%d'/>\n"
             "      </source>\n"
             "      <target dev='%s'/>\n"
             "    </disk>\n",
             data_conns[i].nbd_remote_port, config->disks[i]);
  }

  if (config->removable) {
    for (i = 0; config->removable[i] != NULL; ++i) {
      fprintf (fp,
               "    <disk type='network' device='cdrom'>\n"
               "      <driver name='qemu' type='raw'/>\n"
               "      <target dev='%s'/>\n"
               "    </disk>\n",
               config->removable[i]);
    }
  }

  if (config->interfaces) {
    for (i = 0; config->interfaces[i] != NULL; ++i) {
      CLEANUP_FREE char *mac_filename = NULL;
      CLEANUP_FREE char *mac = NULL;

      if (asprintf (&mac_filename, "/sys/class/net/%s/address",
                    config->interfaces[i]) == -1) {
        perror ("asprintf");
        exit (EXIT_FAILURE);
      }
      if (g_file_get_contents (mac_filename, &mac, NULL, NULL)) {
        size_t len = strlen (mac);

        if (len > 0 && mac[len-1] == '\n')
          mac[len-1] = '\0';
      }

      fprintf (fp,
               "    <interface type='network'>\n"
               "      <source network='default'/>\n"
               "      <target dev='%s'/>\n",
               config->interfaces[i]);
      if (mac)
        fprintf (fp, "      <mac address='%s'/>\n", mac);
      fprintf (fp,
               "    </interface>\n");
    }
  }

  /* Old virt-p2v didn't try to model the graphics hardware. */

  fprintf (fp,
           "  </devices>\n"
           "</domain>\n");
  fclose (fp);

  return ret;
}

static void
debug_parameters (struct config *config)
{
#if DEBUG_STDERR
  size_t i;

  /* Print the conversion parameters and other important information. */
  fprintf (stderr, "local version   .  %s\n", PACKAGE_VERSION);
  fprintf (stderr, "remote version  .  %d.%d.%d\n",
           v2v_major, v2v_minor, v2v_release);
  fprintf (stderr, "remote debugging   %s\n",
           config->verbose ? "true" : "false");
  fprintf (stderr, "conversion server  %s\n",
           config->server ? config->server : "none");
  fprintf (stderr, "port . . . . . .   %d\n", config->port);
  fprintf (stderr, "username . . . .   %s\n",
           config->username ? config->username : "none");
  fprintf (stderr, "password . . . .   %s\n",
           config->password && strlen (config->password) > 0 ? "***" : "none");
  fprintf (stderr, "sudo . . . . . .   %s\n",
           config->sudo ? "true" : "false");
  fprintf (stderr, "guest name . . .   %s\n",
           config->guestname ? config->guestname : "none");
  fprintf (stderr, "vcpus  . . . . .   %d\n", config->vcpus);
  fprintf (stderr, "memory . . . . .   %" PRIu64 "\n", config->memory);
  fprintf (stderr, "disks  . . . . .  ");
  if (config->disks != NULL) {
    for (i = 0; config->disks[i] != NULL; ++i)
      fprintf (stderr, " %s", config->disks[i]);
  }
  fprintf (stderr, "\n");
  fprintf (stderr, "removable  . . .  ");
  if (config->removable != NULL) {
    for (i = 0; config->removable[i] != NULL; ++i)
      fprintf (stderr, " %s", config->removable[i]);
  }
  fprintf (stderr, "\n");
  fprintf (stderr, "interfaces . . .  ");
  if (config->interfaces != NULL) {
    for (i = 0; config->interfaces[i] != NULL; ++i)
      fprintf (stderr, " %s", config->interfaces[i]);
  }
  fprintf (stderr, "\n");
  fprintf (stderr, "\n");
#endif
}
