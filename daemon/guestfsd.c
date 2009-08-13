/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009 Red Hat Inc.
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
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <config.h>

#define _BSD_SOURCE		/* for daemon(3) */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <rpc/types.h>
#include <rpc/xdr.h>
#include <getopt.h>
#include <netdb.h>
#include <sys/param.h>
#include <sys/select.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <ctype.h>
#include <signal.h>
#include <printf.h>

#include "daemon.h"

static void usage (void);

/* Also in guestfs.c */
#define VMCHANNEL_PORT "6666"
#define VMCHANNEL_ADDR "10.0.2.4"

int verbose = 0;

static int print_shell_quote (FILE *stream, const struct printf_info *info, const void *const *args);
static int print_sysroot_shell_quote (FILE *stream, const struct printf_info *info, const void *const *args);
#ifdef HAVE_REGISTER_PRINTF_SPECIFIER
static int print_arginfo (const struct printf_info *info, size_t n, int *argtypes, int *size);
#else
#ifdef HAVE_REGISTER_PRINTF_FUNCTION
static int print_arginfo (const struct printf_info *info, size_t n, int *argtypes);
#else
#error "HAVE_REGISTER_PRINTF_{SPECIFIER|FUNCTION} not defined"
#endif
#endif

/* Location to mount root device. */
const char *sysroot = "/sysroot"; /* No trailing slash. */
int sysroot_len = 8;

int
main (int argc, char *argv[])
{
  static const char *options = "fh:p:?";
  static const struct option long_options[] = {
    { "foreground", 0, 0, 'f' },
    { "help", 0, 0, '?' },
    { "host", 1, 0, 'h' },
    { "port", 1, 0, 'p' },
    { 0, 0, 0, 0 }
  };
  int c, n, r;
  int dont_fork = 0;
  const char *host = NULL;
  const char *port = NULL;
  FILE *fp;
  char buf[4096];
  char *p, *p2;
  int sock;
  struct addrinfo *res, *rr;
  struct addrinfo hints;
  XDR xdr;
  uint32_t len;
  struct sigaction sa;

#ifdef HAVE_REGISTER_PRINTF_SPECIFIER
  /* http://udrepper.livejournal.com/20948.html */
  register_printf_specifier ('Q', print_shell_quote, print_arginfo);
  register_printf_specifier ('R', print_sysroot_shell_quote, print_arginfo);
#else
#ifdef HAVE_REGISTER_PRINTF_FUNCTION
  register_printf_function ('Q', print_shell_quote, print_arginfo);
  register_printf_function ('R', print_sysroot_shell_quote, print_arginfo);
#else
#error "HAVE_REGISTER_PRINTF_{SPECIFIER|FUNCTION} not defined"
#endif
#endif

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, NULL);
    if (c == -1) break;

    switch (c) {
    case 'f':
      dont_fork = 1;
      break;

    case 'h':
      host = optarg;
      break;

    case 'p':
      port = optarg;
      break;

    case '?':
      usage ();
      exit (0);

    default:
      fprintf (stderr, "guestfsd: unexpected command line option 0x%x\n", c);
      exit (1);
    }
  }

  if (optind < argc) {
    usage ();
    exit (1);
  }

  /* If host and port aren't set yet, try /proc/cmdline. */
  if (!host || !port) {
    fp = fopen ("/proc/cmdline", "r");
    if (fp == NULL) {
      perror ("/proc/cmdline");
      goto next;
    }
    n = fread (buf, 1, sizeof buf - 1, fp);
    fclose (fp);
    buf[n] = '\0';

    /* Set the verbose flag.  Not quite right because this will only
     * set the flag if host and port aren't set on the command line.
     * Don't worry about this for now. (XXX)
     */
    verbose = strstr (buf, "guestfs_verbose=1") != NULL;
    if (verbose)
      printf ("verbose daemon enabled\n");

    p = strstr (buf, "guestfs=");

    if (p) {
      p += 8;
      p2 = strchr (p, ':');
      if (p2) {
        *p2++ = '\0';
        host = p;
        r = strcspn (p2, " \n");
        p2[r] = '\0';
        port = p2;
      }
    }
  }

 next:
  /* Can't parse /proc/cmdline, so use built-in defaults. */
  if (!host || !port) {
    host = VMCHANNEL_ADDR;
    port = VMCHANNEL_PORT;
  }

  /* Make sure SIGPIPE doesn't kill us. */
  memset (&sa, 0, sizeof sa);
  sa.sa_handler = SIG_IGN;
  sa.sa_flags = 0;
  if (sigaction (SIGPIPE, &sa, NULL) == -1)
    perror ("sigaction SIGPIPE"); /* but try to continue anyway ... */

  /* Set up a basic environment.  After we are called by /init the
   * environment is essentially empty.
   * https://bugzilla.redhat.com/show_bug.cgi?id=502074#c5
   */
  setenv ("PATH", "/usr/bin:/bin", 1);
  setenv ("SHELL", "/bin/sh", 1);
  setenv ("LC_ALL", "C", 1);

  /* We document that umask defaults to 022 (it should be this anyway). */
  umask (022);

  /* Resolve the hostname. */
  memset (&hints, 0, sizeof hints);
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_flags = AI_ADDRCONFIG;
  r = getaddrinfo (host, port, &hints, &res);
  if (r != 0) {
    fprintf (stderr, "%s:%s: %s\n", host, port, gai_strerror (r));
    exit (1);
  }

  /* Connect to the given TCP socket. */
  sock = -1;
  for (rr = res; rr != NULL; rr = rr->ai_next) {
    sock = socket (rr->ai_family, rr->ai_socktype, rr->ai_protocol);
    if (sock != -1) {
      if (connect (sock, rr->ai_addr, rr->ai_addrlen) == 0)
        break;
      perror ("connect");

      close (sock);
      sock = -1;
    }
  }
  freeaddrinfo (res);

  if (sock == -1) {
    fprintf (stderr, "connection to %s:%s failed\n", host, port);
    exit (1);
  }

  /* Send the magic length message which indicates that
   * userspace is up inside the guest.
   */
  len = GUESTFS_LAUNCH_FLAG;
  xdrmem_create (&xdr, buf, sizeof buf, XDR_ENCODE);
  if (!xdr_uint32_t (&xdr, &len)) {
    fprintf (stderr, "xdr_uint32_t failed\n");
    exit (1);
  }

  (void) xwrite (sock, buf, xdr_getpos (&xdr));

  xdr_destroy (&xdr);

  /* Fork into the background. */
  if (!dont_fork) {
    if (daemon (0, 1) == -1) {
      perror ("daemon");
      exit (1);
    }
  }

  /* Enter the main loop, reading and performing actions. */
  main_loop (sock);

  exit (0);
}

/* Turn "/path" into "/sysroot/path".
 *
 * Caller must check for NULL and call reply_with_perror ("malloc")
 * if it is.  Caller must also free the string.
 *
 * See also the custom %R printf formatter which does shell quoting too.
 */
char *
sysroot_path (const char *path)
{
  char *r;
  int len = strlen (path) + sysroot_len + 1;

  r = malloc (len);
  if (r == NULL)
    return NULL;

  snprintf (r, len, "%s%s", sysroot, path);
  return r;
}

int
xwrite (int sock, const void *buf, size_t len)
{
  int r;

  while (len > 0) {
    r = write (sock, buf, len);
    if (r == -1) {
      perror ("write");
      return -1;
    }
    buf += r;
    len -= r;
  }

  return 0;
}

int
xread (int sock, void *buf, size_t len)
{
  int r;

  while (len > 0) {
    r = read (sock, buf, len);
    if (r == -1) {
      perror ("read");
      return -1;
    }
    if (r == 0) {
      fprintf (stderr, "read: unexpected end of file on fd %d\n", sock);
      return -1;
    }
    buf += r;
    len -= r;
  }

  return 0;
}

static void
usage (void)
{
  fprintf (stderr, "guestfsd [-f] [-h host -p port]\n");
}

int
add_string (char ***argv, int *size, int *alloc, const char *str)
{
  char **new_argv;
  char *new_str;

  if (*size >= *alloc) {
    *alloc += 64;
    new_argv = realloc (*argv, *alloc * sizeof (char *));
    if (new_argv == NULL) {
      reply_with_perror ("realloc");
      free_strings (*argv);
      return -1;
    }
    *argv = new_argv;
  }

  if (str) {
    new_str = strdup (str);
    if (new_str == NULL) {
      reply_with_perror ("strdup");
      free_strings (*argv);
    }
  } else
    new_str = NULL;

  (*argv)[*size] = new_str;

  (*size)++;
  return 0;
}

int
count_strings (char * const* const argv)
{
  int argc;

  for (argc = 0; argv[argc] != NULL; ++argc)
    ;
  return argc;
}

static int
compare (const void *vp1, const void *vp2)
{
  char * const *p1 = (char * const *) vp1;
  char * const *p2 = (char * const *) vp2;
  return strcmp (*p1, *p2);
}

void
sort_strings (char **argv, int len)
{
  qsort (argv, len, sizeof (char *), compare);
}

void
free_strings (char **argv)
{
  int argc;

  for (argc = 0; argv[argc] != NULL; ++argc)
    free (argv[argc]);
  free (argv);
}

void
free_stringslen (char **argv, int len)
{
  int i;

  for (i = 0; i < len; ++i)
    free (argv[i]);
  free (argv);
}

/* This is a more sane version of 'system(3)' for running external
 * commands.  It uses fork/execvp, so we don't need to worry about
 * quoting of parameters, and it allows us to capture any error
 * messages in a buffer.
 */
int
command (char **stdoutput, char **stderror, const char *name, ...)
{
  va_list args;
  char **argv, **p;
  char *s;
  int i, r;

  /* Collect the command line arguments into an array. */
  i = 2;
  argv = malloc (sizeof (char *) * i);
  if (argv == NULL) {
    perror ("malloc");
    return -1;
  }
  argv[0] = (char *) name;
  argv[1] = NULL;

  va_start (args, name);

  while ((s = va_arg (args, char *)) != NULL) {
    p = realloc (argv, sizeof (char *) * (++i));
    if (p == NULL) {
      perror ("realloc");
      free (argv);
      va_end (args);
      return -1;
    }
    argv = p;
    argv[i-2] = s;
    argv[i-1] = NULL;
  }

  va_end (args);

  r = commandv (stdoutput, stderror, argv);

  /* NB: Mustn't free the strings which are on the stack. */
  free (argv);

  return r;
}

/* Same as 'command', but we allow the status code from the
 * subcommand to be non-zero, and return that status code.
 * We still return -1 if there was some other error.
 */
int
commandr (char **stdoutput, char **stderror, const char *name, ...)
{
  va_list args;
  char **argv, **p;
  char *s;
  int i, r;

  /* Collect the command line arguments into an array. */
  i = 2;
  argv = malloc (sizeof (char *) * i);
  if (argv == NULL) {
    perror ("malloc");
    return -1;
  }
  argv[0] = (char *) name;
  argv[1] = NULL;

  va_start (args, name);

  while ((s = va_arg (args, char *)) != NULL) {
    p = realloc (argv, sizeof (char *) * (++i));
    if (p == NULL) {
      perror ("realloc");
      free (argv);
      va_end (args);
      return -1;
    }
    argv = p;
    argv[i-2] = s;
    argv[i-1] = NULL;
  }

  va_end (args);

  r = commandrv (stdoutput, stderror, argv);

  /* NB: Mustn't free the strings which are on the stack. */
  free (argv);

  return r;
}

/* Same as 'command', but passing an argv. */
int
commandv (char **stdoutput, char **stderror, char * const* const argv)
{
  int r;

  r = commandrv (stdoutput, stderror, argv);
  if (r == 0)
    return 0;
  else
    return -1;
}

int
commandrv (char **stdoutput, char **stderror, char * const* const argv)
{
  int so_size = 0, se_size = 0;
  int so_fd[2], se_fd[2];
  pid_t pid;
  int r, quit, i;
  fd_set rset, rset2;
  char buf[256];
  char *p;

  if (stdoutput) *stdoutput = NULL;
  if (stderror) *stderror = NULL;

  if (verbose) {
    printf ("%s", argv[0]);
    for (i = 1; argv[i] != NULL; ++i)
      printf (" %s", argv[i]);
    printf ("\n");
  }

  if (pipe (so_fd) == -1 || pipe (se_fd) == -1) {
    perror ("pipe");
    return -1;
  }

  pid = fork ();
  if (pid == -1) {
    perror ("fork");
    close (so_fd[0]);
    close (so_fd[1]);
    close (se_fd[0]);
    close (se_fd[1]);
    return -1;
  }

  if (pid == 0) {		/* Child process. */
    close (0);
    close (so_fd[0]);
    close (se_fd[0]);
    dup2 (so_fd[1], 1);
    dup2 (se_fd[1], 2);
    close (so_fd[1]);
    close (se_fd[1]);

    execvp (argv[0], argv);
    perror (argv[0]);
    _exit (1);
  }

  /* Parent process. */
  close (so_fd[1]);
  close (se_fd[1]);

  FD_ZERO (&rset);
  FD_SET (so_fd[0], &rset);
  FD_SET (se_fd[0], &rset);

  quit = 0;
  while (quit < 2) {
    rset2 = rset;
    r = select (MAX (so_fd[0], se_fd[0]) + 1, &rset2, NULL, NULL, NULL);
    if (r == -1) {
      perror ("select");
    quit:
      if (stdoutput) free (*stdoutput);
      if (stderror) free (*stderror);
      close (so_fd[0]);
      close (se_fd[0]);
      waitpid (pid, NULL, 0);
      return -1;
    }

    if (FD_ISSET (so_fd[0], &rset2)) { /* something on stdout */
      r = read (so_fd[0], buf, sizeof buf);
      if (r == -1) {
        perror ("read");
        goto quit;
      }
      if (r == 0) { FD_CLR (so_fd[0], &rset); quit++; }

      if (r > 0 && stdoutput) {
        so_size += r;
        p = realloc (*stdoutput, so_size);
        if (p == NULL) {
          perror ("realloc");
          goto quit;
        }
        *stdoutput = p;
        memcpy (*stdoutput + so_size - r, buf, r);
      }
    }

    if (FD_ISSET (se_fd[0], &rset2)) { /* something on stderr */
      r = read (se_fd[0], buf, sizeof buf);
      if (r == -1) {
        perror ("read");
        goto quit;
      }
      if (r == 0) { FD_CLR (se_fd[0], &rset); quit++; }

      if (r > 0 && stderror) {
        se_size += r;
        p = realloc (*stderror, se_size);
        if (p == NULL) {
          perror ("realloc");
          goto quit;
        }
        *stderror = p;
        memcpy (*stderror + se_size - r, buf, r);
      }
    }
  }

  close (so_fd[0]);
  close (se_fd[0]);

  /* Make sure the output buffers are \0-terminated.  Also remove any
   * trailing \n characters from the error buffer (not from stdout).
   */
  if (stdoutput) {
    void *q = realloc (*stdoutput, so_size+1);
    if (q == NULL) {
      perror ("realloc");
      free (*stdoutput);
    }
    *stdoutput = q;
    if (*stdoutput)
      (*stdoutput)[so_size] = '\0';
  }
  if (stderror) {
    void *q = realloc (*stderror, se_size+1);
    if (q == NULL) {
      perror ("realloc");
      free (*stderror);
    }
    *stderror = q;
    if (*stderror) {
      (*stderror)[se_size] = '\0';
      se_size--;
      while (se_size >= 0 && (*stderror)[se_size] == '\n')
        (*stderror)[se_size--] = '\0';
    }
  }

  /* Get the exit status of the command. */
  if (waitpid (pid, &r, 0) != pid) {
    perror ("waitpid");
    return -1;
  }

  if (WIFEXITED (r)) {
    return WEXITSTATUS (r);
  } else
    return -1;
}

/* Split an output string into a NULL-terminated list of lines.
 * Typically this is used where we have run an external command
 * which has printed out a list of things, and we want to return
 * an actual list.
 *
 * The corner cases here are quite tricky.  Note in particular:
 *
 *   "" -> []
 *   "\n" -> [""]
 *   "a\nb" -> ["a"; "b"]
 *   "a\nb\n" -> ["a"; "b"]
 *   "a\nb\n\n" -> ["a"; "b"; ""]
 *
 * The original string is written over and destroyed by this
 * function (which is usually OK because it's the 'out' string
 * from command()).  You can free the original string, because
 * add_string() strdups the strings.
 */
char **
split_lines (char *str)
{
  char **lines = NULL;
  int size = 0, alloc = 0;
  char *p, *pend;

  if (strcmp (str, "") == 0)
    goto empty_list;

  p = str;
  while (p) {
    /* Empty last line? */
    if (p[0] == '\0')
      break;

    pend = strchr (p, '\n');
    if (pend) {
      *pend = '\0';
      pend++;
    }

    if (add_string (&lines, &size, &alloc, p) == -1) {
      return NULL;
    }

    p = pend;
  }

 empty_list:
  if (add_string (&lines, &size, &alloc, NULL) == -1)
    return NULL;

  return lines;
}

/* printf helper function so we can use %Q ("quoted") and %R to print
 * shell-quoted strings.  See HACKING file for more details.
 */
static int
print_shell_quote (FILE *stream,
                   const struct printf_info *info ATTRIBUTE_UNUSED,
                   const void *const *args)
{
#define SAFE(c) (isalnum((c)) ||					\
                 (c) == '/' || (c) == '-' || (c) == '_' || (c) == '.')
  int i, len;
  const char *str = *((const char **) (args[0]));

  for (i = len = 0; str[i]; ++i) {
    if (!SAFE(str[i])) {
      putc ('\\', stream);
      len ++;
    }
    putc (str[i], stream);
    len ++;
  }

  return len;
}

static int
print_sysroot_shell_quote (FILE *stream,
                           const struct printf_info *info,
                           const void *const *args)
{
#define SAFE(c) (isalnum((c)) ||					\
                 (c) == '/' || (c) == '-' || (c) == '_' || (c) == '.')
  fputs (sysroot, stream);
  return sysroot_len + print_shell_quote (stream, info, args);
}

#ifdef HAVE_REGISTER_PRINTF_SPECIFIER
static int
print_arginfo (const struct printf_info *info ATTRIBUTE_UNUSED,
               size_t n, int *argtypes, int *size)
{
  if (n > 0) {
    argtypes[0] = PA_STRING;
    size[0] = sizeof (const char *);
  }
  return 1;
}
#else
#ifdef HAVE_REGISTER_PRINTF_FUNCTION
static int
print_arginfo (const struct printf_info *info, size_t n, int *argtypes)
{
  if (n > 0)
    argtypes[0] = PA_STRING;
  return 1;
}
#else
#error "HAVE_REGISTER_PRINTF_{SPECIFIER|FUNCTION} not defined"
#endif
#endif

/* Perform device name translation.  Don't call this directly -
 * use the RESOLVE_DEVICE macro.
 *
 * See guestfs(3) for the algorithm.
 *
 * We have to open the device and test for ENXIO, because
 * the device nodes themselves will exist in the appliance.
 */
int
device_name_translation (char *device, const char *func)
{
  int fd;

  fd = open (device, O_RDONLY);
  if (fd >= 0) {
    close (fd);
    return 0;
  }

  if (errno != ENXIO && errno != ENOENT) {
  error:
    reply_with_perror ("%s: %s", func, device);
    return -1;
  }

  /* If the name begins with "/dev/sd" then try the alternatives. */
  if (strncmp (device, "/dev/sd", 7) != 0)
    goto error;

  device[5] = 'h';		/* /dev/hd (old IDE driver) */
  fd = open (device, O_RDONLY);
  if (fd >= 0) {
    close (fd);
    return 0;
  }

  device[5] = 'v';		/* /dev/vd (for virtio devices) */
  fd = open (device, O_RDONLY);
  if (fd >= 0) {
    close (fd);
    return 0;
  }

  device[5] = 's';		/* Restore original device name. */
  goto error;
}

/* LVM and other commands aren't synchronous, especially when udev is
 * involved.  eg. You can create or remove some device, but the /dev
 * device node won't appear until some time later.  This means that
 * you get an error if you run one command followed by another.
 * Use 'udevadm settle' after certain commands, but don't be too
 * fussed if it fails.
 */
void
udev_settle (void)
{
  command (NULL, NULL, "/sbin/udevadm", "settle", NULL);
}
