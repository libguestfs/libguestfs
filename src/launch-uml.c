/* libguestfs
 * Copyright (C) 2009-2016 Red Hat Inc.
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
#include <stdbool.h>
#include <inttypes.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/signal.h>
#include <libintl.h>

#include "cloexec.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs_protocol.h"

/* Per-handle data. */
struct backend_uml_data {
  pid_t pid;                    /* vmlinux PID. */
  pid_t recoverypid;            /* Recovery process PID. */

#define UML_UMID_LEN 16
  char umid[UML_UMID_LEN+1];    /* umid=<...> unique ID. */
};

#if 0
static void print_vmlinux_command_line (guestfs_h *g, char **argv);
#endif

/* Run uml_mkcow to create a COW overlay. */
static char *
make_cow_overlay (guestfs_h *g, const char *original)
{
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
  char *overlay;
  int r;

  if (guestfs_int_lazy_make_tmpdir (g) == -1)
    return NULL;

  overlay = safe_asprintf (g, "%s/overlay%d", g->tmpdir, g->unique++);

  guestfs_int_cmd_add_arg (cmd, "uml_mkcow");
  guestfs_int_cmd_add_arg (cmd, overlay);
  guestfs_int_cmd_add_arg (cmd, original);
  r = guestfs_int_cmd_run (cmd);
  if (r == -1) {
    free (overlay);
    return NULL;
  }
  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    guestfs_int_external_command_failed (g, r, "uml_mkcow", original);
    free (overlay);
    return NULL;
  }

  return overlay;
}

static char *
create_cow_overlay_uml (guestfs_h *g, void *datav, struct drive *drv)
{
  return make_cow_overlay (g, drv->src.u.path);
}

#if 0
/* Test for features which are not supported by the UML backend.
 * Possibly some of these should just be warnings, not errors.
 */
static bool
uml_supported (guestfs_h *g)
{
  size_t i;
  struct drive *drv;

  if (g->enable_network) {
    error (g, _("uml backend does not support networking"));
    return false;
  }
  if (g->smp > 1) {
    error (g, _("uml backend does not support SMP"));
    return false;
  }

  ITER_DRIVES (g, i, drv) {
    if (drv->src.protocol != drive_protocol_file) {
      error (g, _("uml backend does not support remote drives"));
      return false;
    }
    if (drv->src.format && STRNEQ (drv->src.format, "raw")) {
      error (g, _("uml backend does not support non-raw-format drives"));
      return false;
    }
    if (drv->iface) {
      error (g,
             _("uml backend does not support drives with 'iface' parameter"));
      return false;
    }
    if (drv->disk_label) {
      error (g,
             _("uml backend does not support drives with 'label' parameter"));
      return false;
    }
    /* Note that discard == "besteffort" is fine. */
    if (drv->discard == discard_enable) {
      error (g,
             _("uml backend does not support drives with 'discard' parameter set to 'enable'"));
      return false;
    }
  }

  return true;
}
#endif

static int
launch_uml (guestfs_h *g, void *datav, const char *arg)
{
  error (g,
	 "launch: In RHEL, only the 'libvirt' or 'direct' method is supported.\n"
	 "In particular, User-Mode Linux (UML) is not supported.");
  return -1;

#if 0
  struct backend_uml_data *data = datav;
  CLEANUP_FREE_STRINGSBUF DECLARE_STRINGSBUF (cmdline);
  int console_sock = -1, daemon_sock = -1;
  int r;
  int csv[2], dsv[2];
  CLEANUP_FREE char *kernel = NULL, *dtb = NULL,
    *initrd = NULL, *appliance = NULL;
  int has_appliance_drive;
  CLEANUP_FREE char *appliance_cow = NULL;
  uint32_t size;
  CLEANUP_FREE void *buf = NULL;
  struct drive *drv;
  size_t i;
  struct hv_param *hp;
  char *term = getenv ("TERM");

  if (!uml_supported (g))
    return -1;

  if (!g->nr_drives) {
    error (g, _("you must call guestfs_add_drive before guestfs_launch"));
    return -1;
  }

  /* Assign a random unique ID to this run. */
  if (guestfs_int_random_string (data->umid, UML_UMID_LEN) == -1) {
    perrorf (g, "guestfs_int_random_string");
    return -1;
  }

  /* Locate and/or build the appliance. */
  if (guestfs_int_build_appliance (g, &kernel, &dtb, &initrd, &appliance) == -1)
    return -1;
  has_appliance_drive = appliance != NULL;

  /* Create COW overlays for the appliance.  Note that the documented
   * syntax ubd0=cow,orig does not work since kernel 3.3.  See:
   * http://thread.gmane.org/gmane.linux.uml.devel/13556
   */
  if (has_appliance_drive) {
    appliance_cow = make_cow_overlay (g, appliance);
    if (!appliance_cow)
      goto cleanup0;
  }

  /* The socket that the daemon will talk to us on.
   */
  if (socketpair (AF_LOCAL, SOCK_STREAM|SOCK_CLOEXEC, 0, dsv) == -1) {
    perrorf (g, "socketpair");
    goto cleanup0;
  }

  /* The console socket. */
  if (!g->direct_mode) {
    if (socketpair (AF_LOCAL, SOCK_STREAM|SOCK_CLOEXEC, 0, csv) == -1) {
      perrorf (g, "socketpair");
      close (dsv[0]);
      close (dsv[1]);
      goto cleanup0;
    }
  }

  /* Construct the vmlinux command line.  We have to do this before
   * forking, because after fork we are not allowed to use
   * non-signal-safe functions such as malloc.
   */
#define ADD_CMDLINE(str)			\
  guestfs_int_add_string (g, &cmdline, (str))
#define ADD_CMDLINE_PRINTF(fs,...)				\
  guestfs_int_add_sprintf (g, &cmdline, (fs), ##__VA_ARGS__)

  ADD_CMDLINE (g->hv);

  /* Give this instance a unique random ID. */
  ADD_CMDLINE_PRINTF ("umid=%s", data->umid);

  /* Set memory size. */
  ADD_CMDLINE_PRINTF ("mem=%dM", g->memsize);

  /* vmlinux appears to ignore this, but let's add it anyway. */
  ADD_CMDLINE_PRINTF ("initrd=%s", initrd);

  /* Make sure our appliance init script runs first. */
  ADD_CMDLINE ("init=/init");

  /* This tells the /init script not to reboot at the end. */
  ADD_CMDLINE ("guestfs_noreboot=1");

  /* Root filesystem should be mounted read-write (default seems to
   * be "ro").
   */
  ADD_CMDLINE ("rw");

  /* See also guestfs_int_appliance_command_line. */
  if (g->verbose)
    ADD_CMDLINE ("guestfs_verbose=1");

  ADD_CMDLINE ("panic=1");

  ADD_CMDLINE_PRINTF ("TERM=%s", term ? term : "linux");

  if (g->selinux)
    ADD_CMDLINE ("selinux=1 enforcing=0");
  else
    ADD_CMDLINE ("selinux=0");

  /* XXX This isn't quite right.  Multiple append args won't work. */
  if (g->append)
    ADD_CMDLINE (g->append);

  /* Add the drives. */
  ITER_DRIVES (g, i, drv) {
    if (!drv->overlay)
      ADD_CMDLINE_PRINTF ("ubd%zu=%s", i, drv->src.u.path);
    else
      ADD_CMDLINE_PRINTF ("ubd%zu=%s", i, drv->overlay);
  }

  /* Add the ext2 appliance drive (after all the drives). */
  if (has_appliance_drive) {
    char drv_name[64] = "ubd";
    guestfs_int_drive_name (g->nr_drives, &drv_name[3]);

    ADD_CMDLINE_PRINTF ("ubd%zu=%s", g->nr_drives, appliance_cow);
    ADD_CMDLINE_PRINTF ("root=/dev/%s", drv_name);
  }

  /* Create the daemon socket. */
  ADD_CMDLINE_PRINTF ("ssl3=fd:%d", dsv[1]);
  ADD_CMDLINE ("guestfs_channel=/dev/ttyS3");

  /* Add any vmlinux parameters. */
  for (hp = g->hv_params; hp; hp = hp->next) {
    ADD_CMDLINE (hp->hv_param);
    if (hp->hv_value)
      ADD_CMDLINE (hp->hv_value);
  }

  /* Finish off the command line. */
  guestfs_int_end_stringsbuf (g, &cmdline);

  r = fork ();
  if (r == -1) {
    perrorf (g, "fork");
    if (!g->direct_mode) {
      close (csv[0]);
      close (csv[1]);
    }
    close (dsv[0]);
    close (dsv[1]);
    goto cleanup0;
  }

  if (r == 0) {                 /* Child (vmlinux). */
    /* Set up the daemon socket for the child. */
    close (dsv[0]);
    set_cloexec_flag (dsv[1], 0); /* so it doesn't close across exec */

    if (!g->direct_mode) {
      /* Set up stdin, stdout, stderr. */
      close (0);
      close (1);
      close (csv[0]);

      /* We set the FD_CLOEXEC flag on the socket above, but now (in
       * the child) it's safe to unset this flag so vmlinux can use the
       * socket.
       */
      set_cloexec_flag (csv[1], 0);

      /* Stdin. */
      if (dup (csv[1]) == -1) {
      dup_failed:
        perror ("dup failed");
        _exit (EXIT_FAILURE);
      }
      /* Stdout. */
      if (dup (csv[1]) == -1)
        goto dup_failed;

      /* Send stderr to the pipe as well. */
      close (2);
      if (dup (csv[1]) == -1)
        goto dup_failed;

      close (csv[1]);

      /* RHBZ#1123007 */
      close_file_descriptors (fd > 2 && fd != dsv[1]);
    }

    /* Dump the command line (after setting up stderr above). */
    if (g->verbose)
      print_vmlinux_command_line (g, cmdline.argv);

    /* Put vmlinux in a new process group. */
    if (g->pgroup)
      setpgid (0, 0);

    setenv ("LC_ALL", "C", 1);

    execv (g->hv, cmdline.argv); /* Run vmlinux. */
    perror (g->hv);
    _exit (EXIT_FAILURE);
  }

  /* Parent (library). */
  data->pid = r;

  /* Fork the recovery process off which will kill vmlinux if the
   * parent process fails to do so (eg. if the parent segfaults).
   */
  data->recoverypid = -1;
  if (g->recovery_proc) {
    r = fork ();
    if (r == 0) {
      struct sigaction sa;
      pid_t vmlinux_pid = data->pid;
      pid_t parent_pid = getppid ();

      /* Remove all signal handlers.  See the justification here:
       * https://www.redhat.com/archives/libvir-list/2008-August/msg00303.html
       * We don't mask signal handlers yet, so this isn't completely
       * race-free, but better than not doing it at all.
       */
      memset (&sa, 0, sizeof sa);
      sa.sa_handler = SIG_DFL;
      sa.sa_flags = 0;
      sigemptyset (&sa.sa_mask);
      for (i = 1; i < NSIG; ++i)
        sigaction (i, &sa, NULL);

      /* Close all other file descriptors.  This ensures that we don't
       * hold open (eg) pipes from the parent process.
       */
      close_file_descriptors (1);

      /* It would be nice to be able to put this in the same process
       * group as vmlinux (ie. setpgid (0, vmlinux_pid)).  However
       * this is not possible because we don't have any guarantee here
       * that the vmlinux process has started yet.
       */
      if (g->pgroup)
        setpgid (0, 0);

      /* Writing to argv is hideously complicated and error prone.  See:
       * http://git.postgresql.org/gitweb/?p=postgresql.git;a=blob;f=src/backend/utils/misc/ps_status.c;hb=HEAD
       */

      /* Loop around waiting for one or both of the other processes to
       * disappear.  It's fair to say this is very hairy.  The PIDs that
       * we are looking at might be reused by another process.  We are
       * effectively polling.  Is the cure worse than the disease?
       */
      for (;;) {
        if (kill (vmlinux_pid, 0) == -1)
          /* vmlinux's gone away, we aren't needed */
          _exit (EXIT_SUCCESS);
        if (kill (parent_pid, 0) == -1) {
          /* Parent's gone away, vmlinux still around, so kill vmlinux. */
          kill (data->pid, SIGKILL);
          _exit (EXIT_SUCCESS);
        }
        sleep (2);
      }
    }

    /* Don't worry, if the fork failed, this will be -1.  The recovery
     * process isn't essential.
     */
    data->recoverypid = r;
  }

  if (!g->direct_mode) {
    /* Close the other end of the console socketpair. */
    close (csv[1]);

    console_sock = csv[0];      /* stdin of child */
    csv[0] = -1;
  }

  daemon_sock = dsv[0];
  close (dsv[1]);
  dsv[0] = -1;

  g->state = LAUNCHING;

  /* Wait for vmlinux to start and to connect back to us via
   * virtio-serial and send the GUESTFS_LAUNCH_FLAG message.
   */
  g->conn =
    guestfs_int_new_conn_socket_connected (g, daemon_sock, console_sock);
  if (!g->conn)
    goto cleanup1;

  /* g->conn now owns these sockets. */
  daemon_sock = console_sock = -1;

  /* We now have to wait for vmlinux to start up, the daemon to start
   * running, and for it to send the GUESTFS_LAUNCH_FLAG to us.
   */
  r = guestfs_int_recv_from_daemon (g, &size, &buf);

  if (r == -1) {
    guestfs_int_launch_failed_error (g);
    goto cleanup1;
  }

  if (size != GUESTFS_LAUNCH_FLAG) {
    guestfs_int_launch_failed_error (g);
    goto cleanup1;
  }

  debug (g, "appliance is up");

  /* This is possible in some really strange situations, such as
   * guestfsd starts up OK but then vmlinux immediately exits.  Check
   * for it because the caller is probably expecting to be able to
   * send commands after this function returns.
   */
  if (g->state != READY) {
    error (g, _("vmlinux launched and contacted daemon, but state != READY"));
    goto cleanup1;
  }

  if (has_appliance_drive)
    guestfs_int_add_dummy_appliance_drive (g);

  return 0;

 cleanup1:
  if (!g->direct_mode && csv[0] >= 0)
    close (csv[0]);
  if (dsv[0] >= 0)
    close (dsv[0]);
  if (data->pid > 0) kill (data->pid, SIGKILL);
  if (data->recoverypid > 0) kill (data->recoverypid, SIGKILL);
  if (data->pid > 0) guestfs_int_waitpid_noerror (data->pid);
  if (data->recoverypid > 0) guestfs_int_waitpid_noerror (data->recoverypid);
  data->pid = 0;
  data->recoverypid = 0;
  memset (&g->launch_t, 0, sizeof g->launch_t);

 cleanup0:
  if (daemon_sock >= 0)
    close (daemon_sock);
  if (console_sock >= 0)
    close (console_sock);
  if (g->conn) {
    g->conn->ops->free_connection (g, g->conn);
    g->conn = NULL;
  }
  g->state = CONFIG;
  return -1;
#endif
}

#if 0
/* This is called from the forked subprocess just before vmlinux runs,
 * so it can just print the message straight to stderr, where it will
 * be picked up and funnelled through the usual appliance event API.
 */
static void
print_vmlinux_command_line (guestfs_h *g, char **argv)
{
  size_t i = 0;
  int needs_quote;

  struct timeval tv;
  gettimeofday (&tv, NULL);
  fprintf (stderr, "[%05" PRIi64 "ms] ",
           guestfs_int_timeval_diff (&g->launch_t, &tv));

  while (argv[i]) {
    if (i > 0) fputc (' ', stderr);

    /* Does it need shell quoting?  This only deals with simple cases. */
    needs_quote = strcspn (argv[i], " ") != strlen (argv[i]);

    if (needs_quote) fputc ('\'', stderr);
    fprintf (stderr, "%s", argv[i]);
    if (needs_quote) fputc ('\'', stderr);
    i++;
  }

  fputc ('\n', stderr);
}
#endif

static int
shutdown_uml (guestfs_h *g, void *datav, int check_for_errors)
{
  struct backend_uml_data *data = datav;
  int ret = 0;
  int status;

  /* Signal vmlinux to shutdown cleanly, and kill the recovery process. */
  if (data->pid > 0) {
    debug (g, "sending SIGTERM to process %d", data->pid);
    kill (data->pid, SIGTERM);
  }
  if (data->recoverypid > 0) kill (data->recoverypid, 9);

  /* Wait for subprocess(es) to exit. */
  if (data->pid > 0) {
    if (guestfs_int_waitpid (g, data->pid, &status, "vmlinux") == -1)
      ret = -1;
    /* Note it's normal for the pre-3.11 vmlinux process to exit with
     * status "killed by signal 15" (where 15 == SIGTERM).  Post 3.11
     * the exit status can normally be 1.
     *
     * So don't consider those to be an error.
     */
    else if (!(WIFSIGNALED (status) && WTERMSIG (status) == SIGTERM) &&
             !(WIFEXITED (status) && WEXITSTATUS (status) == 0) &&
             !(WIFEXITED (status) && WEXITSTATUS (status) == 1)) {
      guestfs_int_external_command_failed (g, status, g->hv, NULL);
      ret = -1;
    }
  }
  if (data->recoverypid > 0) guestfs_int_waitpid_noerror (data->recoverypid);

  data->pid = data->recoverypid = 0;

  return ret;
}

static int
get_pid_uml (guestfs_h *g, void *datav)
{
  struct backend_uml_data *data = datav;

  if (data->pid > 0)
    return data->pid;
  else {
    error (g, "get_pid: no vmlinux subprocess");
    return -1;
  }
}

/* UML appears to use a single major, and puts ubda at minor 0 with
 * each partition at minors 1-15, ubdb at minor 16, etc.  So the
 * maximum is 256/16 = 16.  However one disk is used by the appliance,
 * so it's one less than this.  I tested both 15 & 16 disks, and found
 * that 15 worked and 16 failed.
 */
static int
max_disks_uml (guestfs_h *g, void *datav)
{
  return 15;
}

static struct backend_ops backend_uml_ops = {
  .data_size = sizeof (struct backend_uml_data),
  .create_cow_overlay = create_cow_overlay_uml,
  .launch = launch_uml,
  .shutdown = shutdown_uml,
  .get_pid = get_pid_uml,
  .max_disks = max_disks_uml,
};

void
guestfs_int_init_uml_backend (void)
{
  guestfs_int_register_backend ("uml", &backend_uml_ops);
}
