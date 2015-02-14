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
#include <libintl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <arpa/inet.h>
#include <netinet/in.h>

#include <glib.h>

#include <libxml/xmlwriter.h>

#include "miniexpect.h"
#include "p2v.h"

/* How long to wait for qemu-nbd to start (seconds). */
#define WAIT_QEMU_NBD_TIMEOUT 10

/* Data per NBD connection / physical disk. */
struct data_conn {
  mexp_h *h;                /* miniexpect handle to ssh */
  pid_t nbd_pid;            /* qemu pid */
  int nbd_local_port;       /* local NBD port on physical machine */
  int nbd_remote_port;      /* remote NBD port on conversion server */
};

static int send_quoted (mexp_h *, const char *s);
static pid_t start_qemu_nbd (int nbd_local_port, const char *device);
static int wait_qemu_nbd (int nbd_local_port, int timeout_seconds);
static void cleanup_data_conns (struct data_conn *data_conns, size_t nr);
static char *generate_libvirt_xml (struct config *, struct data_conn *);
static const char *map_interface_to_network (struct config *, const char *interface);
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

static volatile sig_atomic_t stop = 0;

#pragma GCC diagnostic ignored "-Wsuggest-attribute=noreturn"
int
start_conversion (struct config *config,
                  void (*notify_ui) (int type, const char *data))
{
  int ret = -1;
  int status;
  size_t i, len;
  size_t nr_disks = guestfs_int_count_strings (config->disks);
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

    if (config->disks[i][0] == '/') {
      device = strdup (config->disks[i]);
      if (!device) {
        perror ("strdup");
        cleanup_data_conns (data_conns, nr_disks);
        exit (EXIT_FAILURE);
      }
    }
    else if (asprintf (&device, "/dev/%s", config->disks[i]) == -1) {
      perror ("asprintf");
      cleanup_data_conns (data_conns, nr_disks);
      exit (EXIT_FAILURE);
    }

    /* Start qemu-nbd listening on the given port number. */
    data_conns[i].nbd_pid =
      start_qemu_nbd (data_conns[i].nbd_local_port, device);
    if (data_conns[i].nbd_pid == 0)
      goto out;

    /* Wait for qemu-nbd to listen */
    if (wait_qemu_nbd (data_conns[i].nbd_local_port,
                       WAIT_QEMU_NBD_TIMEOUT) == -1)
      goto out;

#if DEBUG_STDERR
    fprintf (stderr,
             "%s: data connection for %s: SSH remote port %d, local port %d\n",
             guestfs_int_program_name, device,
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
  guestfs_int_random_string (&remote_dir[len-8], 8);
  if (notify_ui)
    notify_ui (NOTIFY_LOG_DIR, remote_dir);

  /* Generate the libvirt XML. */
  libvirt_xml = generate_libvirt_xml (config, data_conns);
  if (libvirt_xml == NULL)
    goto out;

#if DEBUG_STDERR
  fprintf (stderr, "%s: libvirt XML:\n%s", guestfs_int_program_name, libvirt_xml);
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

  /* Build the virt-v2v command up in pieces to make the quoting
   * slightly more sane.
   */
  if (mexp_printf (control_h, "( %s virt-v2v%s -i libvirtxml",
                   config->sudo ? "sudo " : "",
                   config->verbose ? " -v -x" : "") == -1) {
  printf_fail:
    set_conversion_error ("mexp_printf: virt-v2v command: %m");
    goto out;
  }
  if (config->output) {         /* -o */
    if (mexp_printf (control_h, " -o ") == -1)
      goto printf_fail;
    if (send_quoted (control_h, config->output) == -1)
      goto printf_fail;
  }
  switch (config->output_allocation) { /* -oa */
  case OUTPUT_ALLOCATION_NONE:
    /* nothing */
    break;
  case OUTPUT_ALLOCATION_SPARSE:
    if (mexp_printf (control_h, " -oa sparse") == -1)
      goto printf_fail;
    break;
  case OUTPUT_ALLOCATION_PREALLOCATED:
    if (mexp_printf (control_h, " -oa preallocated") == -1)
      goto printf_fail;
    break;
  default:
    abort ();
  }
  if (config->output_format) {  /* -of */
    if (mexp_printf (control_h, " -of ") == -1)
      goto printf_fail;
    if (send_quoted (control_h, config->output_format) == -1)
      goto printf_fail;
  }
  if (config->output_storage) { /* -os */
    if (mexp_printf (control_h, " -os ") == -1)
      goto printf_fail;
    if (send_quoted (control_h, config->output_storage) == -1)
      goto printf_fail;
  }
  if (mexp_printf (control_h, " --root first") == -1)
    goto printf_fail;
  if (mexp_printf (control_h, " %s/physical.xml", remote_dir) == -1)
    goto printf_fail;
  /* no stdin, and send stdout and stderr to the same place */
  if (mexp_printf (control_h, " </dev/null 2>&1") == -1)
    goto printf_fail;
  if (mexp_printf (control_h, " ; echo $? > %s/status", remote_dir) == -1)
    goto printf_fail;
  if (mexp_printf (control_h, " ) | tee %s/virt-v2v-conversion-log.txt",
                   remote_dir) == -1)
    goto printf_fail;
  if (mexp_printf (control_h, "; exit $(< %s/status)", remote_dir) == -1)
    goto printf_fail;
  if (mexp_printf (control_h, "\n") == -1)
    goto printf_fail;

  /* Read output from the virt-v2v process and echo it through the
   * notify function, until virt-v2v closes the connection.
   */
  while (!stop) {
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

  if (stop) {
    set_conversion_error ("cancelled by user");
    goto out;
  }

  if (notify_ui)
    notify_ui (NOTIFY_STATUS, _("Control connection closed by remote."));

  ret = 0;
 out:
  if (control_h) {
    if ((status = mexp_close (control_h)) == -1) {
      set_conversion_error ("mexp_close: %m");
      ret = -1;
    } else if (ret == 0 &&
               WIFEXITED (status) &&
               WEXITSTATUS (status) != 0) {
      set_conversion_error ("virt-v2v exited with status %d",
                            WEXITSTATUS (status));
      ret = -1;
    }
  }
  cleanup_data_conns (data_conns, nr_disks);
  return ret;
}

void
cancel_conversion (void)
{
  stop = 1;
}

/* Send a shell-quoted string to remote. */
static int
send_quoted (mexp_h *h, const char *s)
{
  if (mexp_printf (h, "\"") == -1)
    return -1;
  while (*s) {
    if (*s == '$' || *s == '`' || *s == '\\' || *s == '"') {
      if (mexp_printf (h, "\\") == -1)
        return -1;
    }
    if (mexp_printf (h, "%c", *s) == -1)
      return -1;
    ++s;
  }
  if (mexp_printf (h, "\"") == -1)
    return -1;
  return 0;
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

static int
wait_qemu_nbd (int nbd_local_port, int timeout_seconds)
{
  int sockfd;
  int result = -1;
  int reuseaddr = 1;
  struct sockaddr_in src_addr, dst_addr;
  time_t start_t, now_t;
  struct timeval timeout = { .tv_usec = 0 };
  char magic[8]; /* NBDMAGIC */
  size_t bytes_read = 0;
  ssize_t recvd;

  time (&start_t);

  sockfd = socket (AF_INET, SOCK_STREAM, 0);
  if (sockfd == -1) {
    perror ("socket");
    return -1;
  }

  memset (&src_addr, 0, sizeof src_addr);
  src_addr.sin_family = AF_INET;
  /* Source port for probing qemu-nbd should be one greater than
   * nbd_local_port.  It's not guaranteed to always bind to this port,
   * but it will hint the kernel to start there and try incrementally
   * higher ports if needed.  This avoids the case where the kernel
   * selects nbd_local_port as our source port, and we immediately
   * connect to ourself.  See:
   * https://bugzilla.redhat.com/show_bug.cgi?id=1167774#c9
   */
  src_addr.sin_port = htons (nbd_local_port+1);
  inet_pton (AF_INET, "localhost", &src_addr.sin_addr);

  memset (&dst_addr, 0, sizeof dst_addr);
  dst_addr.sin_family = AF_INET;
  dst_addr.sin_port = htons (nbd_local_port);
  inet_pton (AF_INET, "localhost", &dst_addr.sin_addr);

  /* If we run p2v repeatedly (say, running the tests in a loop),
   * there's a decent chance we'll end up trying to bind() to a port
   * that is in TIME_WAIT from a prior run.  Handle that gracefully
   * with SO_REUSEADDR.
   */
  if (setsockopt (sockfd, SOL_SOCKET, SO_REUSEADDR,
                  &reuseaddr, sizeof reuseaddr) == -1) {
    set_conversion_error ("waiting for qemu-nbd to start: setsockopt: %m");
    goto cleanup;
  }

  if (bind (sockfd, (struct sockaddr *) &src_addr, sizeof src_addr) == -1) {
    set_conversion_error ("waiting for qemu-nbd to start: bind(%d): %m",
                          ntohs (src_addr.sin_port));
    goto cleanup;
  }

  for (;;) {
    time (&now_t);

    if (now_t - start_t >= timeout_seconds) {
      set_conversion_error ("waiting for qemu-nbd to start: connect: %m");
      goto cleanup;
    }

    if (connect (sockfd, (struct sockaddr *) &dst_addr, sizeof dst_addr) == 0)
      break;
  }

  time (&now_t);
  timeout.tv_sec = (start_t + timeout_seconds) - now_t;
  setsockopt (sockfd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);

  do {
    recvd = recv (sockfd, magic, sizeof magic - bytes_read, 0);

    if (recvd == -1) {
      set_conversion_error ("waiting for qemu-nbd to start: recv: %m");
      goto cleanup;
    }

    bytes_read += recvd;
  } while (bytes_read < sizeof magic);

  if (memcmp (magic, "NBDMAGIC", sizeof magic) != 0) {
    set_conversion_error ("waiting for qemu-nbd to start: "
                          "'NBDMAGIC' was not received from qemu-nbd");
    goto cleanup;
  }

  result = 0;
cleanup:
  close (sockfd);

  return result;
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

/* Macros "inspired" by src/launch-libvirt.c */
/* <element */
#define start_element(element)                                        \
  if (xmlTextWriterStartElement (xo, BAD_CAST (element)) == -1) {     \
    set_conversion_error ("xmlTextWriterStartElement: %m");           \
    return NULL;                                                      \
  }                                                                   \
  do

/* finish current </element> */
#define end_element()                                                   \
  while (0);                                                            \
  do {                                                                  \
    if (xmlTextWriterEndElement (xo) == -1) {                           \
      set_conversion_error ("xmlTextWriterEndElement: %m");             \
      return NULL;                                                      \
    }                                                                   \
  } while (0)

/* <element/> */
#define empty_element(element) \
  do { start_element(element) {} end_element (); } while (0)

/* key=value attribute of the current element. */
#define attribute(key,value)                                            \
  if (xmlTextWriterWriteAttribute (xo, BAD_CAST (key), BAD_CAST (value)) == -1) { \
    set_conversion_error ("xmlTextWriterWriteAttribute: %m");           \
    return NULL;                                                        \
  }

/* key=value, but value is a printf-style format string. */
#define attribute_format(key,fs,...)                                    \
  if (xmlTextWriterWriteFormatAttribute (xo, BAD_CAST (key),            \
                                           fs, ##__VA_ARGS__) == -1) {  \
    set_conversion_error ("xmlTextWriterWriteFormatAttribute: %m");     \
    return NULL;                                                        \
  }

/* A string, eg. within an element. */
#define string(str)                                                     \
  if (xmlTextWriterWriteString (xo, BAD_CAST (str)) == -1) {            \
    set_conversion_error ("xmlTextWriterWriteString: %m");              \
    return NULL;                                                        \
  }

/* A string, using printf-style formatting. */
#define string_format(fs,...)                                           \
  if (xmlTextWriterWriteFormatString (xo, fs, ##__VA_ARGS__) == -1) {   \
    set_conversion_error ("xmlTextWriterWriteFormatString: %m");        \
    return NULL;                                                        \
  }

/* An XML comment. */
#define comment(str)                                                  \
  if (xmlTextWriterWriteComment (xo, BAD_CAST (str)) == -1) {         \
    set_conversion_error ("xmlTextWriterWriteComment: %m");           \
    return NULL;                                                      \
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
  char *ret;
  CLEANUP_XMLBUFFERFREE xmlBufferPtr xb = NULL;
  xmlOutputBufferPtr ob;
  CLEANUP_XMLFREETEXTWRITER xmlTextWriterPtr xo = NULL;
  size_t i;

  xb = xmlBufferCreate ();
  if (xb == NULL) {
    set_conversion_error ("xmlBufferCreate: %m");
    return NULL;
  }
  ob = xmlOutputBufferCreateBuffer (xb, NULL);
  if (ob == NULL) {
    set_conversion_error ("xmlOutputBufferCreateBuffer: %m");
    return NULL;
  }
  xo = xmlNewTextWriter (ob);
  if (xo == NULL) {
    set_conversion_error ("xmlNewTextWriter: %m");
    return NULL;
  }

  if (xmlTextWriterSetIndent (xo, 1) == -1 ||
      xmlTextWriterSetIndentString (xo, BAD_CAST "  ") == -1) {
    set_conversion_error ("could not set XML indent: %m");
    return NULL;
  }
  if (xmlTextWriterStartDocument (xo, NULL, NULL, NULL) == -1) {
    set_conversion_error ("xmlTextWriterStartDocument: %m");
    return NULL;
  }

  memkb = config->memory / 1024;

  comment
    (" NOTE!\n"
     "\n"
     "  This libvirt XML is generated by the virt-p2v front end, in\n"
     "  order to communicate with the backend virt-v2v process running\n"
     "  on the conversion server.  It is a minimal description of the\n"
     "  physical machine.  If the target of the conversion is libvirt,\n"
     "  then virt-v2v will generate the real target libvirt XML, which\n"
     "  has only a little to do with the XML in this file.\n"
     "\n"
     "  TL;DR: Don't try to load this XML into libvirt. ");

  start_element ("domain") {
    attribute ("type", "physical");

    start_element ("name") {
      string (config->guestname);
    } end_element ();

    start_element ("memory") {
      attribute ("unit", "KiB");
      string_format ("%" PRIu64, memkb);
    } end_element ();

    start_element ("currentMemory") {
      attribute ("unit", "KiB");
      string_format ("%" PRIu64, memkb);
    } end_element ();

    start_element ("vcpu") {
      string_format ("%d", config->vcpus);
    } end_element ();

    start_element ("os") {
      start_element ("type") {
        attribute ("arch", host_cpu);
        string ("hvm");
      } end_element ();
    } end_element ();

    start_element ("features") {
      if (config->flags & FLAG_ACPI) empty_element ("acpi");
      if (config->flags & FLAG_APIC) empty_element ("apic");
      if (config->flags & FLAG_PAE)  empty_element ("pae");
    } end_element ();

    start_element ("devices") {

      for (i = 0; config->disks[i] != NULL; ++i) {
        char target_dev[64];

        if (config->disks[i][0] == '/') {
        target_sd:
          memcpy (target_dev, "sd", 2);
          guestfs_int_drive_name (i, &target_dev[2]);
        } else {
          if (strlen (config->disks[i]) <= sizeof (target_dev) - 1)
            strcpy (target_dev, config->disks[i]);
          else
            goto target_sd;
        }

        start_element ("disk") {
          attribute ("type", "network");
          attribute ("device", "disk");
          start_element ("driver") {
            attribute ("name", "qemu");
            attribute ("type", "raw");
          } end_element ();
          start_element ("source") {
            attribute ("protocol", "nbd");
            start_element ("host") {
              attribute ("name", "localhost");
              attribute_format ("port", "%d", data_conns[i].nbd_remote_port);
            } end_element ();
          } end_element ();
          start_element ("target") {
            attribute ("dev", target_dev);
            /* XXX Need to set bus to "ide" or "scsi" here. */
          } end_element ();
        } end_element ();
      }

      if (config->removable) {
        for (i = 0; config->removable[i] != NULL; ++i) {
          start_element ("disk") {
            attribute ("type", "network");
            attribute ("device", "cdrom");
            start_element ("driver") {
              attribute ("name", "qemu");
              attribute ("type", "raw");
            } end_element ();
            start_element ("target") {
              attribute ("dev", config->removable[i]);
            } end_element ();
          } end_element ();
        }
      }

      if (config->interfaces) {
        for (i = 0; config->interfaces[i] != NULL; ++i) {
          const char *target_network;
          CLEANUP_FREE char *mac_filename = NULL;
          CLEANUP_FREE char *mac = NULL;

          target_network =
            map_interface_to_network (config, config->interfaces[i]);

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

          start_element ("interface") {
            attribute ("type", "network");
            start_element ("source") {
              attribute ("network", target_network);
            } end_element ();
            start_element ("target") {
              attribute ("dev", config->interfaces[i]);
            } end_element ();
            if (mac) {
              start_element ("mac") {
                attribute ("address", mac);
              } end_element ();
            }
          } end_element ();
        }
      }

    } end_element (); /* </devices> */

  } end_element (); /* </domain> */

  if (xmlTextWriterEndDocument (xo) == -1) {
    set_conversion_error ("xmlTextWriterEndDocument: %m");
    return NULL;
  }
  ret = (char *) xmlBufferDetach (xb); /* caller frees */
  if (ret == NULL) {
    set_conversion_error ("xmlBufferDetach: %m");
    return NULL;
  }

  return ret;
}

/* Using config->network_map, map the interface to a target network
 * name.  If no map is found, return "default".  See virt-p2v(1)
 * documentation of "p2v.network" for how the network map works.
 *
 * Note this returns a static string which is only valid as long as
 * config->network_map is not freed.
 */
static const char *
map_interface_to_network (struct config *config, const char *interface)
{
  size_t i, len;

  if (config->network_map == NULL)
    return "default";

  for (i = 0; config->network_map[i] != NULL; ++i) {
    /* The default map maps everything. */
    if (strchr (config->network_map[i], ':') == NULL)
      return config->network_map[i];

    /* interface: ? */
    len = strlen (interface);
    if (STRPREFIX (config->network_map[i], interface) &&
        config->network_map[i][len] == ':')
      return &config->network_map[i][len+1];
  }

  /* No mapping found. */
  return "default";
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
  fprintf (stderr, "network map  . .  ");
  if (config->network_map != NULL) {
    for (i = 0; config->network_map[i] != NULL; ++i)
      fprintf (stderr, " %s", config->network_map[i]);
  }
  fprintf (stderr, "\n");
  fprintf (stderr, "output . . . . .   %s\n",
           config->output ? config->output : "none");
  fprintf (stderr, "output alloc . .   %d\n", config->output_allocation);
  fprintf (stderr, "output conn  . .   %s\n",
           config->output_connection ? config->output_connection : "none");
  fprintf (stderr, "output format  .   %s\n",
           config->output_format ? config->output_format : "none");
  fprintf (stderr, "output storage .   %s\n",
           config->output_storage ? config->output_storage : "none");
  fprintf (stderr, "\n");
#endif
}
