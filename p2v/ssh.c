/* virt-p2v
 * Copyright (C) 2009-2015 Red Hat Inc.
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

/* This file handles the ssh connections to the conversion server.
 *
 * virt-p2v will open several connections over the lifetime of
 * the conversion process.
 *
 * In 'test_connection', it will first open a connection (to check it
 * is possible) and query virt-v2v on the server to ensure it exists,
 * it is the right version, and so on.  This connection is then
 * closed, because in the GUI case we don't want to deal with keeping
 * it alive in case the administrator has set up an autologout.
 *
 * Once we start conversion, we will open a control connection to send
 * the libvirt configuration data and to start up virt-v2v, and we
 * will open up one data connection per local hard disk.  The data
 * connection(s) have a reverse port forward to the local qemu-nbd
 * server which is serving the content of that hard disk.  The remote
 * port for each data connection is assigned by ssh.  See
 * 'open_data_connection' and 'start_remote_conversion'.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <inttypes.h>
#include <unistd.h>
#include <errno.h>
#include <locale.h>
#include <assert.h>
#include <libintl.h>
#include <sys/types.h>
#include <sys/wait.h>

#include "ignore-value.h"

#include "miniexpect.h"
#include "p2v.h"

int v2v_major;
int v2v_minor;
int v2v_release;
char **input_drivers = NULL;
char **output_drivers = NULL;

static char *ssh_error;

static void set_ssh_error (const char *fs, ...)
  __attribute__((format(printf,1,2)));

static void
set_ssh_error (const char *fs, ...)
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

  free (ssh_error);
  ssh_error = msg;
}

const char *
get_ssh_error (void)
{
  return ssh_error;
}

static void compile_regexps (void) __attribute__((constructor));
static void free_regexps (void) __attribute__((destructor));

static pcre *password_re;
static pcre *prompt_re;
static pcre *version_re;
static pcre *feature_libguestfs_rewrite_re;
static pcre *feature_input_re;
static pcre *feature_output_re;
static pcre *portfwd_re;

static void
compile_regexps (void)
{
  const char *err;
  int offset;
  int p;

  /* These regexps are always used for partial matching.  In pcre < 8
   * there were limitations on the regexps possible for partial
   * matching, so fail if that is true here.  In pcre >= 8, all
   * regexps can be used in a partial match.
   */
#define CHECK_PARTIAL_OK(pattern, re)					\
  do {									\
    pcre_fullinfo ((re), NULL, PCRE_INFO_OKPARTIAL, &p);		\
    if (p != 1) {							\
      fprintf (stderr, "%s: %s:%d: internal error: pattern '%s' cannot be used for partial matching\n", \
	       guestfs_int_program_name,				\
	       __FILE__, __LINE__, (pattern));				\
      abort ();								\
    }									\
  } while (0)

#define COMPILE(re,pattern,options)                                     \
  do {                                                                  \
    re = pcre_compile ((pattern), (options), &err, &offset, NULL);      \
    if (re == NULL) {                                                   \
      ignore_value (write (2, err, strlen (err)));                      \
      abort ();                                                         \
    }                                                                   \
    CHECK_PARTIAL_OK ((pattern), re);					\
  } while (0)

  COMPILE (password_re, "assword", 0);
  /* The magic synchronization strings all match this expression.  See
   * start_ssh function below.
   */
  COMPILE (prompt_re,
	   "###((?:[0123456789abcdefghijklmnopqrstuvwxyz]){8})### ", 0);
  COMPILE (version_re,
           "virt-v2v ([1-9](?:\\d)*)\\.([1-9](?:\\d)*)\\.(0|[1-9](?:\\d)*)",
	   0);
  COMPILE (feature_libguestfs_rewrite_re, "libguestfs-rewrite", 0);
  COMPILE (feature_input_re, "input:((?:\\w)*)", 0);
  COMPILE (feature_output_re, "output:((?:\\w)*)", 0);
  COMPILE (portfwd_re, "Allocated port ((?:\\d)+) for remote forward", 0);
}

static void
free_regexps (void)
{
  pcre_free (password_re);
  pcre_free (prompt_re);
  pcre_free (version_re);
  pcre_free (feature_libguestfs_rewrite_re);
  pcre_free (feature_input_re);
  pcre_free (feature_output_re);
  pcre_free (portfwd_re);
}

/* Start ssh subprocess with the standard arguments and possibly some
 * optional arguments.  Also handles password authentication.
 */
static mexp_h *
start_ssh (struct config *config, char **extra_args, int wait_prompt)
{
  size_t i, j, nr_args, count;
  char port_str[64];
  CLEANUP_FREE /* [sic] */ const char **args = NULL;
  mexp_h *h;
  const int ovecsize = 12;
  int ovector[ovecsize];
  int saved_timeout;

  /* Create the ssh argument array. */
  nr_args = 0;
  if (extra_args != NULL)
    nr_args = guestfs_int_count_strings (extra_args);

  nr_args += 11;
  args = malloc (sizeof (char *) * nr_args);
  if (args == NULL) {
    perror ("malloc");
    exit (EXIT_FAILURE);
  }
  j = 0;
  args[j++] = "ssh";
  args[j++] = "-p";             /* Port. */
  snprintf (port_str, sizeof port_str, "%d", config->port);
  args[j++] = port_str;
  args[j++] = "-l";             /* Username. */
  args[j++] = config->username ? config->username : "root";
  args[j++] = "-o";             /* Host key will always be novel. */
  args[j++] = "StrictHostKeyChecking=no";
  args[j++] = "-o";            /* Only use password authentication. */
  args[j++] = "PreferredAuthentications=keyboard-interactive,password";
  if (extra_args != NULL) {
    for (i = 0; extra_args[i] != NULL; ++i)
      args[j++] = extra_args[i];
  }
  args[j++] = config->server;   /* Conversion server. */
  args[j++] = NULL;
  assert (j == nr_args);

  h = mexp_spawnv ("ssh", (char **) args);
  if (h == NULL)
    return NULL;

  if (config->password && strlen (config->password) > 0) {
    /* Wait for the password prompt. */
    switch (mexp_expect (h,
                         (mexp_regexp[]) {
                           { 100, .re = password_re },
                           { 0 }
                         }, ovector, ovecsize)) {
    case 100:                   /* Got password prompt. */
      if (mexp_printf (h, "%s\n", config->password) == -1) {
        set_ssh_error ("mexp_printf: %m");
        mexp_close (h);
        return NULL;
      }
      break;

    case MEXP_EOF:
      mexp_close (h);
      set_ssh_error ("unexpected end of file waiting for password prompt");
      return NULL;

    case MEXP_TIMEOUT:
      mexp_close (h);
      set_ssh_error ("timeout waiting for password prompt");
      return NULL;

    case MEXP_ERROR:
      set_ssh_error ("mexp_expect: %m");
      mexp_close (h);
      return NULL;

    case MEXP_PCRE_ERROR:
      set_ssh_error ("PCRE error: %d\n", h->pcre_error);
      mexp_close (h);
      return NULL;
    }
  }

  if (!wait_prompt)
    return h;

  /* Synchronize with the command prompt and set it to a known string. */

  /* Note that we cannot control the initial prompt.  It would involve
   * changing the remote SSH configuration (AcceptEnv).  However what
   * we can do is to repeatedly send 'export PS1=<magic>' commands
   * until we synchronize with the remote shell.
   */
  saved_timeout = h->timeout;
  h->timeout = 2000;

  for (count = 0; count < 30; ++count) {
    char magic[9];
    const char *matched;
    int r;

    if (guestfs_int_random_string (magic, 8) == -1) {
      set_ssh_error ("random_string: %m");
      mexp_close (h);
      return NULL;
    }

    /* The purpose of the '' inside the string is to ensure we don't
     * mistake the command echo for the prompt.
     */
    if (mexp_printf (h, "export PS1='###''%s''### '\n", magic) == -1) {
      set_ssh_error ("random_string: %m");
      mexp_close (h);
      return NULL;
    }

    /* Wait for the prompt. */
  wait_again:
    switch (mexp_expect (h,
                         (mexp_regexp[]) {
                           { 100, .re = password_re },
                           { 101, .re = prompt_re },
                           { 0 }
                         }, ovector, ovecsize)) {
    case 100:                    /* Got password prompt unexpectedly. */
      if (mexp_printf (h, "%s\n", config->password) == -1) {
        mexp_close (h);
        set_ssh_error ("unexpected password prompt: probably the password supplied is wrong");
        return NULL;
      }
      break;

    case 101:
      /* Got a prompt.  However it might be an earlier prompt.  If it
       * doesn't match the PS1 string we sent, then repeat the expect.
       */
      r = pcre_get_substring (h->buffer, ovector, h->pcre_error, 1, &matched);
      if (r < 0) {
        fprintf (stderr, "error: PCRE error reading substring (%d)\n", r);
        exit (EXIT_FAILURE);
      }
      r = STREQ (magic, matched);
      pcre_free_substring (matched);
      if (!r)
        goto wait_again;
      goto got_prompt;

    case MEXP_EOF:
      mexp_close (h);
      set_ssh_error ("unexpected end of file waiting for command prompt");
      return NULL;

    case MEXP_TIMEOUT:
      /* Timeout here is not an error, since ssh may "eat" commands that
       * we send before the shell at the other end is ready.  Just loop.
       */
      break;

    case MEXP_ERROR:
      set_ssh_error ("mexp_expect: %m");
      mexp_close (h);
      return NULL;

    case MEXP_PCRE_ERROR:
      set_ssh_error ("PCRE error: %d\n", h->pcre_error);
      mexp_close (h);
      return NULL;
    }
  }

  mexp_close (h);
  set_ssh_error ("failed to synchronize with remote shell after 60 seconds");
  return NULL;

 got_prompt:
  h->timeout = saved_timeout;

  return h;
}

static void add_input_driver (const char *name, size_t len);
static void add_output_driver (const char *name, size_t len);

#pragma GCC diagnostic ignored "-Wsuggest-attribute=noreturn" /* WTF? */
int
test_connection (struct config *config)
{
  mexp_h *h;
  CLEANUP_FREE char *major_str = NULL, *minor_str = NULL, *release_str = NULL;
  int feature_libguestfs_rewrite = 0;
  int status;
  const int ovecsize = 12;
  int ovector[ovecsize];

  h = start_ssh (config, NULL, 1);
  if (h == NULL)
    return -1;

  /* Clear any previous version information since we may be connecting
   * to a different server.
   */
  v2v_major = v2v_minor = v2v_release = 0;

  /* Send 'virt-v2v --version' command and hope we get back a version string.
   * Note old virt-v2v did not understand -V option.
   */
  if (mexp_printf (h,
                   "%svirt-v2v --version\n",
                   config->sudo ? "sudo " : "") == -1) {
    set_ssh_error ("mexp_printf: %m");
    mexp_close (h);
    return -1;
  }

  for (;;) {
    switch (mexp_expect (h,
                         (mexp_regexp[]) {
                           { 100, .re = version_re },
                           { 101, .re = prompt_re },
                           { 0 }
                         }, ovector, ovecsize)) {
    case 100:                   /* Got version string. */
      major_str = strndup (&h->buffer[ovector[2]], ovector[3]-ovector[2]);
      minor_str = strndup (&h->buffer[ovector[4]], ovector[5]-ovector[4]);
      release_str = strndup (&h->buffer[ovector[6]], ovector[7]-ovector[6]);
      sscanf (major_str, "%d", &v2v_major);
      sscanf (minor_str, "%d", &v2v_minor);
      sscanf (release_str, "%d", &v2v_release);
#if DEBUG_STDERR
      fprintf (stderr, "%s: remote virt-v2v version: %d.%d.%d\n",
               guestfs_int_program_name, v2v_major, v2v_minor, v2v_release);
#endif
      /* This is an internal error.  Need to check this here so we
       * don't confuse it with the no-version case below.
       */
      if (v2v_major < 1) {
        mexp_close (h);
        set_ssh_error ("could not parse version string");
        return -1;
      }
      break;

    case 101:             /* Got the prompt. */
      goto end_of_version;

    case MEXP_EOF:
      mexp_close (h);
      set_ssh_error ("unexpected end of file waiting virt-v2v --version output");
      return -1;

    case MEXP_TIMEOUT:
      mexp_close (h);
      set_ssh_error ("timeout waiting for virt-v2v --version output");
      return -1;

    case MEXP_ERROR:
      set_ssh_error ("mexp_expect: %m");
      mexp_close (h);
      return -1;

    case MEXP_PCRE_ERROR:
      set_ssh_error ("PCRE error: %d\n", h->pcre_error);
      mexp_close (h);
      return -1;
    }
  }
 end_of_version:

  /* Got the prompt but no version number. */
  if (v2v_major == 0) {
    mexp_close (h);
    set_ssh_error ("virt-v2v is not installed on the conversion server, "
                   "or it might be a too old version");
    return -1;
  }

  /* The major version must always be 1. */
  if (v2v_major != 1) {
    mexp_close (h);
    set_ssh_error ("virt-v2v major version is not 1 (major = %d), "
                   "this version of virt-p2v is not compatible", v2v_major);
    return -1;
  }

  /* The version of virt-v2v must be >= 1.28, just to make sure
   * someone isn't (a) using one of the experimental 1.27 releases
   * that we published during development, nor (b) using old virt-v2v.
   * We should remain compatible with any virt-v2v after 1.28.
   */
  if (v2v_minor < 28) {
    mexp_close (h);
    set_ssh_error ("virt-v2v version is < 1.28 (major = %d, minor = %d), "
                   "you must upgrade to virt-v2v >= 1.28 on "
                   "the conversion server", v2v_major, v2v_minor);
    return -1;
  }

  /* Clear any previous driver information since we may be connecting
   * to a different server.
   */
  guestfs_int_free_string_list (input_drivers);
  guestfs_int_free_string_list (output_drivers);
  input_drivers = output_drivers = NULL;

  /* Get virt-v2v features.  See: v2v/cmdline.ml */
  if (mexp_printf (h, "%svirt-v2v --machine-readable\n",
                   config->sudo ? "sudo " : "") == -1) {
    set_ssh_error ("mexp_printf: %m");
    mexp_close (h);
    return -1;
  }

  for (;;) {
    switch (mexp_expect (h,
                         (mexp_regexp[]) {
                           { 100, .re = feature_libguestfs_rewrite_re },
                           { 101, .re = feature_input_re },
                           { 102, .re = feature_output_re },
                           { 103, .re = prompt_re },
                           { 0 }
                         }, ovector, ovecsize)) {
    case 100:                   /* libguestfs-rewrite. */
      feature_libguestfs_rewrite = 1;
      break;

    case 101:
      /* input:<driver-name> corresponds to an -i option in virt-v2v. */
      add_input_driver (&h->buffer[ovector[2]],
                        (size_t) (ovector[3]-ovector[2]));
      break;

    case 102:
      /* output:<driver-name> corresponds to an -o option in virt-v2v. */
      add_output_driver (&h->buffer[ovector[2]],
                         (size_t) (ovector[3]-ovector[2]));
      break;

    case 103:                   /* Got prompt, so end of output. */
      goto end_of_machine_readable;

    case MEXP_EOF:
      mexp_close (h);
      set_ssh_error ("unexpected end of file waiting virt-v2v --machine-readable output");
      return -1;

    case MEXP_TIMEOUT:
      mexp_close (h);
      set_ssh_error ("timeout waiting virt-v2v --machine-readable output");
      return -1;

    case MEXP_ERROR:
      set_ssh_error ("mexp_expect: %m");
      mexp_close (h);
      return -1;

    case MEXP_PCRE_ERROR:
      set_ssh_error ("PCRE error: %d\n", h->pcre_error);
      mexp_close (h);
      return -1;
    }
  }
 end_of_machine_readable:

  if (!feature_libguestfs_rewrite) {
    mexp_close (h);
    set_ssh_error ("invalid output of virt-v2v --machine-readable command");
    return -1;
  }

  /* Test finished, shut down ssh. */
  if (mexp_printf (h, "exit\n") == -1) {
    set_ssh_error ("mexp_printf: %m");
    mexp_close (h);
    return -1;
  }

  switch (mexp_expect (h, NULL, NULL, 0)) {
  case MEXP_EOF:
    break;

  case MEXP_TIMEOUT:
    mexp_close (h);
    set_ssh_error ("timeout waiting for end of ssh session");
    return -1;

  case MEXP_ERROR:
    set_ssh_error ("mexp_expect: %m");
    mexp_close (h);
    return -1;

  case MEXP_PCRE_ERROR:
    set_ssh_error ("PCRE error: %d\n", h->pcre_error);
    mexp_close (h);
    return -1;
  }

  status = mexp_close (h);
  if (!((WIFEXITED (status) && WEXITSTATUS (status) == 0)
        || (WIFSIGNALED (status) && WTERMSIG (status) == SIGHUP))) {
    set_ssh_error ("unexpected close status from ssh subprocess (%d)", status);
    return -1;
  }

  return 0;
}

static void
add_option (const char *type, char ***drivers, const char *name, size_t len)
{
  size_t n;

  if (*drivers == NULL)
    n = 0;
  else
    n = guestfs_int_count_strings (*drivers);

  n++;

  *drivers = realloc (*drivers, (n+1) * sizeof (char *));
  if (*drivers == NULL) {
    perror ("malloc");
    exit (EXIT_FAILURE);
  }

  (*drivers)[n-1] = strndup (name, len);
  if ((*drivers)[n-1] == NULL) {
    perror ("strndup");
    exit (EXIT_FAILURE);
  }
  (*drivers)[n] = NULL;

#if DEBUG_STDERR
  fprintf (stderr, "%s: remote virt-v2v supports %s driver %s\n",
           guestfs_int_program_name, type, (*drivers)[n-1]);
#endif
}

static void
add_input_driver (const char *name, size_t len)
{
  add_option ("input", &input_drivers, name, len);
}

static void
add_output_driver (const char *name, size_t len)
{
  add_option ("output", &output_drivers, name, len);
}

/* The p2v ISO should allow us to open up just about any port. */
static int nbd_local_port = 50123;

mexp_h *
open_data_connection (struct config *config, int *local_port, int *remote_port)
{
  mexp_h *h;
  char remote_arg[32];
  const char *extra_args[] = {
    "-R", remote_arg,
    "-N",
    NULL
  };
  CLEANUP_FREE char *port_str = NULL;
  const int ovecsize = 12;
  int ovector[ovecsize];

  snprintf (remote_arg, sizeof remote_arg, "0:localhost:%d", nbd_local_port);
  *local_port = nbd_local_port;
  nbd_local_port++;

  h = start_ssh (config, (char **) extra_args, 0);
  if (h == NULL)
    return NULL;

  switch (mexp_expect (h,
                       (mexp_regexp[]) {
                         { 100, .re = portfwd_re },
                         { 0 }
                       }, ovector, ovecsize)) {
  case 100:                     /* Ephemeral port. */
    port_str = strndup (&h->buffer[ovector[2]], ovector[3]-ovector[2]);
    if (port_str == NULL) {
      set_ssh_error ("not enough memory for strndup");
      mexp_close (h);
      return NULL;
    }
    if (sscanf (port_str, "%d", remote_port) != 1) {
      set_ssh_error ("cannot extract the port number from '%s'", port_str);
      mexp_close (h);
      return NULL;
    }
    break;

  case MEXP_EOF:
    mexp_close (h);
    set_ssh_error ("unexpected end of file waiting ssh -R output");
    return NULL;

  case MEXP_TIMEOUT:
    mexp_close (h);
    set_ssh_error ("timeout waiting for ssh -R output");
    return NULL;

  case MEXP_ERROR:
    set_ssh_error ("mexp_expect: %m");
    mexp_close (h);
    return NULL;

  case MEXP_PCRE_ERROR:
    set_ssh_error ("PCRE error: %d\n", h->pcre_error);
    mexp_close (h);
    return NULL;
  }

  return h;
}

/* Wait for the prompt. */
static int
wait_for_prompt (mexp_h *h)
{
  const int ovecsize = 12;
  int ovector[ovecsize];

  switch (mexp_expect (h,
                       (mexp_regexp[]) {
                         { 100, .re = prompt_re },
                         { 0 }
                       }, ovector, ovecsize)) {
  case 100:                     /* Got the prompt. */
    return 0;

  case MEXP_EOF:
    set_ssh_error ("unexpected end of file waiting for prompt");
    return -1;

  case MEXP_TIMEOUT:
    set_ssh_error ("timeout waiting for prompt");
    return -1;

  case MEXP_ERROR:
    set_ssh_error ("mexp_expect: %m");
    return -1;

  case MEXP_PCRE_ERROR:
    set_ssh_error ("PCRE error: %d\n", h->pcre_error);
    return -1;
  }

  return 0;
}

mexp_h *
start_remote_connection (struct config *config,
                         const char *remote_dir, const char *libvirt_xml, const char *config_xml)
{
  mexp_h *h;
  char magic[9];

  if (guestfs_int_random_string (magic, 8) == -1) {
    perror ("random_string");
    return NULL;
  }

  h = start_ssh (config, NULL, 1);
  if (h == NULL)
    return NULL;

  /* Create the remote directory. */
  if (mexp_printf (h, "mkdir %s\n", remote_dir) == -1) {
    set_ssh_error ("mexp_printf: %m");
    goto error;
  }

  if (wait_for_prompt (h) == -1)
    goto error;

  /* Write some useful config information to files in the remote directory. */
  if (mexp_printf (h, "echo '%s' > %s/name\n",
                   config->guestname, remote_dir) == -1) {
    set_ssh_error ("mexp_printf: %m");
    goto error;
  }

  if (strcmp (config->output, "everrunft") == 0 || strcmp (config->output, "everrunha") == 0)
  {
    if (mexp_printf (h, "echo '%s' > %s/config.xml\n",
                   config_xml, remote_dir) == -1) {
      set_ssh_error ("mexp_printf: %m");
      goto error;
    }
  }


  if (wait_for_prompt (h) == -1)
    goto error;

  if (mexp_printf (h, "date > %s/time\n", remote_dir) == -1) {
    set_ssh_error ("mexp_printf: %m");
    goto error;
  }

  if (wait_for_prompt (h) == -1)
    goto error;

  /* Upload the guest libvirt XML to the remote directory. */
  if (mexp_printf (h,
                   "cat > '%s/physical.xml' << '__%s__'\n"
                   "%s"
                   "__%s__\n",
                   remote_dir, magic,
                   libvirt_xml,
                   magic) == -1) {
    set_ssh_error ("mexp_printf: %m");
    goto error;
  }

  if (wait_for_prompt (h) == -1)
    goto error;

  return h;

 error:
  mexp_close (h);
  return NULL;
}
