/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2017 Red Hat Inc.
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

/**
 * This is the guestfs daemon which runs inside the guestfs appliance.
 * This file handles start up, connecting back to the library, and has
 * several utility functions.
 */

#include <config.h>

#ifdef HAVE_WINDOWS_H
# include <windows.h>
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <rpc/types.h>
#include <rpc/xdr.h>
#include <getopt.h>
#include <sys/param.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <signal.h>
#include <netdb.h>
#include <sys/select.h>
#include <sys/wait.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <errno.h>
#include <error.h>
#include <assert.h>
#include <termios.h>

#ifdef HAVE_PRINTF_H
# include <printf.h>
#endif

#include <augeas.h>

#include "sockets.h"
#include "c-ctype.h"
#include "ignore-value.h"
#include "error.h"

#include "daemon.h"

GUESTFSD_EXT_CMD(str_udevadm, udevadm);
GUESTFSD_EXT_CMD(str_uuidgen, uuidgen);

#ifndef MAX
# define MAX(a,b) ((a)>(b)?(a):(b))
#endif

/* Not the end of the world if this open flag is not defined. */
#ifndef O_CLOEXEC
# define O_CLOEXEC 0
#endif

/* If root device is an ext2 filesystem, this is the major and minor.
 * This is so we can ignore this device from the point of view of the
 * user, eg. in guestfs_list_devices and many other places.
 */
static dev_t root_device = 0;

int verbose = 0;
int enable_network = 0;

static void makeraw (const char *channel, int fd);
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

#ifdef WIN32
static int
winsock_init (void)
{
  int r;

  /* http://msdn2.microsoft.com/en-us/library/ms742213.aspx */
  r = gl_sockets_startup (SOCKETS_2_2);
  return r == 0 ? 0 : -1;
}
#else /* !WIN32 */
static int
winsock_init (void)
{
  return 0;
}
#endif /* !WIN32 */

/* Location to mount root device. */
const char *sysroot = "/sysroot"; /* No trailing slash. */
size_t sysroot_len = 8;

/* If set (the default), do 'umount-all' when performing autosync. */
int autosync_umount = 1;

/* If set, we are testing the daemon as part of the libguestfs tests. */
int test_mode = 0;

/* Name of the virtio-serial channel. */
#define VIRTIO_SERIAL_CHANNEL "/dev/virtio-ports/org.libguestfs.channel.0"

static void
usage (void)
{
  fprintf (stderr,
	   "guestfsd [-r] [-v|--verbose]\n");
}

int
main (int argc, char *argv[])
{
  static const char options[] = "c:lnrtv?";
  static const struct option long_options[] = {
    { "help", 0, 0, '?' },
    { "channel", 1, 0, 'c' },
    { "listen", 0, 0, 'l' },
    { "network", 0, 0, 'n' },
    { "test", 0, 0, 't' },
    { "verbose", 0, 0, 'v' },
    { 0, 0, 0, 0 }
  };
  int c;
  const char *channel = NULL;
  int listen_mode = 0;

  ignore_value (chdir ("/"));

  if (winsock_init () == -1)
    error (EXIT_FAILURE, 0, "winsock initialization failed");

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

  /* XXX The appliance /init script sets LD_PRELOAD=../libSegFault.so.
   * However if we CHROOT_IN to the sysroot that file might not exist,
   * resulting in all commands failing.  What we'd really like to do
   * is to have LD_PRELOAD only set while outside the chroot.  I
   * suspect the proper way to solve this is to remove the
   * CHROOT_IN/_OUT hack and replace it properly (fork), but that is
   * for another day.
   */
  unsetenv ("LD_PRELOAD");

  struct stat statbuf;
  if (stat ("/", &statbuf) == 0)
    root_device = statbuf.st_dev;

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, NULL);
    if (c == -1) break;

    switch (c) {
    case 'c':
      channel = optarg;
      break;

    case 'l':
      listen_mode = 1;
      break;

    case 'n':
      enable_network = 1;
      break;

      /* The -r flag is used when running standalone.  It changes
       * several aspects of the daemon.
       */
    case 'r':
      sysroot = "";
      sysroot_len = 0;
      autosync_umount = 0;
      break;

      /* Undocumented --test option used for testing guestfsd. */
    case 't':
      test_mode = 1;
      break;

    case 'v':
      verbose = 1;
      break;

    case '?':
      usage ();
      exit (EXIT_SUCCESS);

    default:
      error (EXIT_FAILURE, 0,
             "unexpected command line option 0x%x\n", (unsigned) c);
    }
  }

  if (optind < argc) {
    usage ();
    exit (EXIT_FAILURE);
  }

#ifndef WIN32
  /* Make sure SIGPIPE doesn't kill us. */
  struct sigaction sa;
  memset (&sa, 0, sizeof sa);
  sa.sa_handler = SIG_IGN;
  sa.sa_flags = 0;
  if (sigaction (SIGPIPE, &sa, NULL) == -1)
    perror ("sigaction SIGPIPE"); /* but try to continue anyway ... */
#endif

#ifdef WIN32
# define setenv(n,v,f) _putenv(n "=" v)
#endif
  /* Set up a basic environment.  After we are called by /init the
   * environment is essentially empty.
   * https://bugzilla.redhat.com/show_bug.cgi?id=502074#c5
   */
  if (!test_mode)
    setenv ("PATH", "/sbin:/usr/sbin:/bin:/usr/bin", 1);
  setenv ("SHELL", "/bin/sh", 1);
  setenv ("LC_ALL", "C", 1);
  setenv ("TERM", "dumb", 1);

#ifndef WIN32
  /* We document that umask defaults to 022 (it should be this anyway). */
  umask (022);
#else
  /* This is the default for Windows anyway.  It's not even clear if
   * Windows ever uses this -- the MSDN documentation for the function
   * contains obvious errors.
   */
  _umask (0);
#endif

  /* Make a private copy of /etc/lvm so we can change the config (see
   * daemon/lvm-filter.c).
   */
  if (!test_mode) {
    copy_lvm ();
    start_lvmetad ();
  }

  /* Connect to virtio-serial channel. */
  if (!channel)
    channel = VIRTIO_SERIAL_CHANNEL;

  if (verbose)
    printf ("trying to open virtio-serial channel '%s'\n", channel);

  int sock;
  if (!listen_mode) {
    if (STRPREFIX (channel, "fd:")) {
      if (sscanf (channel+3, "%d", &sock) != 1)
        error (EXIT_FAILURE, 0, "cannot parse --channel %s", channel);
    }
    else {
      sock = open (channel, O_RDWR|O_CLOEXEC);
      if (sock == -1) {
        fprintf (stderr,
                 "\n"
                 "Failed to connect to virtio-serial channel.\n"
                 "\n"
                 "This is a fatal error and the appliance will now exit.\n"
                 "\n"
                 "Usually this error is caused by either QEMU or the appliance\n"
                 "kernel not supporting the vmchannel method that the\n"
                 "libguestfs library chose to use.  Please run\n"
                 "'libguestfs-test-tool' and provide the complete, unedited\n"
                 "output to the libguestfs developers, either in a bug report\n"
                 "or on the libguestfs redhat com mailing list.\n"
                 "\n");
        error (EXIT_FAILURE, errno, "open: %s", channel);
      }
    }
  }
  else {
    struct sockaddr_un addr;

    sock = socket (AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC, 0);
    if (sock == -1)
      error (EXIT_FAILURE, errno, "socket");
    addr.sun_family = AF_UNIX;
    if (strlen (channel) > UNIX_PATH_MAX-1)
      error (EXIT_FAILURE, 0, "%s: socket path is too long", channel);
    strcpy (addr.sun_path, channel);

    if (bind (sock, (struct sockaddr *) &addr, sizeof addr) == -1)
      error (EXIT_FAILURE, errno, "bind: %s", channel);

    if (listen (sock, 4) == -1)
      error (EXIT_FAILURE, errno, "listen");

    sock = accept4 (sock, NULL, NULL, SOCK_CLOEXEC);
    if (sock == -1)
      error (EXIT_FAILURE, errno, "accept");
  }

  /* If it's a serial-port like device then it probably has echoing
   * enabled.  Put it into complete raw mode.
   */
  if (STRPREFIX (channel, "/dev/ttyS"))
    makeraw (channel, sock);

  /* Wait for udev devices to be created.  If you start libguestfs,
   * especially with disks that contain complex (eg. mdadm) data
   * already, then it is possible for the 'mdadm' and LVM commands
   * that the init script runs to have not completed by the time the
   * daemon starts executing library commands.  (This is very rare and
   * hard to test however, but we have seen it in 'brew').  Run
   * udev_settle, but do it as late as possible to minimize the chance
   * that we'll have to do any waiting here.
   */
  udev_settle ();

  /* Send the magic length message which indicates that
   * userspace is up inside the guest.
   */
  char lenbuf[4];
  XDR xdr;
  uint32_t len = GUESTFS_LAUNCH_FLAG;
  xdrmem_create (&xdr, lenbuf, sizeof lenbuf, XDR_ENCODE);
  xdr_u_int (&xdr, &len);

  if (xwrite (sock, lenbuf, sizeof lenbuf) == -1)
    error (EXIT_FAILURE, errno, "xwrite");

  xdr_destroy (&xdr);

  /* Enter the main loop, reading and performing actions. */
  main_loop (sock);

  exit (EXIT_SUCCESS);
}

/* Try to make the socket raw, but don't fail if it's not possible. */
static void
makeraw (const char *channel, int fd)
{
  struct termios tt;

  if (tcgetattr (fd, &tt) == -1) {
    fprintf (stderr, "tcgetattr: ");
    perror (channel);
    return;
  }

  cfmakeraw (&tt);
  if (tcsetattr (fd, TCSANOW, &tt) == -1) {
    fprintf (stderr, "tcsetattr: ");
    perror (channel);
  }
}

/**
 * Return true iff device is the root device (and therefore should be
 * ignored from the point of view of user calls).
 */
static int
is_root_device_stat (struct stat *statbuf)
{
  if (statbuf->st_rdev == root_device) return 1;
  return 0;
}

int
is_root_device (const char *device)
{
  struct stat statbuf;

  udev_settle_file (device);

  if (stat (device, &statbuf) == -1) {
    perror (device);
    return 0;
  }

  return is_root_device_stat (&statbuf);
}

/**
 * Turn C<"/path"> into C<"/sysroot/path">.
 *
 * Returns C<NULL> on failure.  The caller I<must> check for this and
 * call S<C<reply_with_perror ("malloc")>>.  The caller must also free
 * the returned string.
 *
 * See also the custom C<%R> printf formatter which does shell quoting too.
 */
char *
sysroot_path (const char *path)
{
  char *r;
  const size_t len = strlen (path) + sysroot_len + 1;

  r = malloc (len);
  if (r == NULL)
    return NULL;

  snprintf (r, len, "%s%s", sysroot, path);
  return r;
}

/**
 * Resolve path within sysroot, calling C<sysroot_path> on the
 * resolved path.
 *
 * Returns C<NULL> on failure.  The caller I<must> check for this and
 * call S<C<reply_with_perror ("malloc")>>.  The caller must also free
 * the returned string.
 *
 * See also the custom C<%R> printf formatter which does shell quoting too.
 */
char *
sysroot_realpath (const char *path)
{
  CLEANUP_FREE char *rp = NULL;

  CHROOT_IN;
  rp = realpath (path, NULL);
  CHROOT_OUT;
  if (rp == NULL)
    return NULL;

  return sysroot_path (rp);
}

int
xwrite (int sock, const void *v_buf, size_t len)
{
  ssize_t r;
  const char *buf = v_buf;

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
xread (int sock, void *v_buf, size_t len)
{
  int r;
  char *buf = v_buf;

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

int
add_string_nodup (struct stringsbuf *sb, char *str)
{
  char **new_argv;

  if (sb->size >= sb->alloc) {
    sb->alloc += 64;
    new_argv = realloc (sb->argv, sb->alloc * sizeof (char *));
    if (new_argv == NULL) {
      reply_with_perror ("realloc");
      free (str);
      return -1;
    }
    sb->argv = new_argv;
  }

  sb->argv[sb->size] = str;
  sb->size++;

  return 0;
}

int
add_string (struct stringsbuf *sb, const char *str)
{
  char *new_str = NULL;

  if (str) {
    new_str = strdup (str);
    if (new_str == NULL) {
      reply_with_perror ("strdup");
      return -1;
    }
  }

  return add_string_nodup (sb, new_str);
}

int
add_sprintf (struct stringsbuf *sb, const char *fs, ...)
{
  va_list args;
  char *str;
  int r;

  va_start (args, fs);
  r = vasprintf (&str, fs, args);
  va_end (args);
  if (r == -1) {
    reply_with_perror ("vasprintf");
    return -1;
  }

  return add_string_nodup (sb, str);
}

int
end_stringsbuf (struct stringsbuf *sb)
{
  return add_string_nodup (sb, NULL);
}

void
free_stringsbuf (struct stringsbuf *sb)
{
  if (sb->argv != NULL)
    free_stringslen (sb->argv, sb->size);
}

/* Take the ownership of the strings of the strings buffer,
 * resetting it to a null buffer.
 */
char **
take_stringsbuf (struct stringsbuf *sb)
{
  DECLARE_STRINGSBUF (null);
  char **ret = sb->argv;
  *sb = null;
  return ret;
}

size_t
count_strings (char *const *argv)
{
  size_t argc;

  for (argc = 0; argv[argc] != NULL; ++argc)
    ;
  return argc;
}

/**
 * Returns true if C<v> is a power of 2.
 *
 * Uses the algorithm described at
 * L<http://graphics.stanford.edu/~seander/bithacks.html#DetermineIfPowerOf2>
 */
int
is_power_of_2 (unsigned long v)
{
  return v && ((v & (v - 1)) == 0);
}

static int
compare (const void *vp1, const void *vp2)
{
  char * const *p1 = (char * const *) vp1;
  char * const *p2 = (char * const *) vp2;
  return strcmp (*p1, *p2);
}

void
sort_strings (char **argv, size_t len)
{
  qsort (argv, len, sizeof (char *), compare);
}

void
free_strings (char **argv)
{
  size_t argc;

  if (!argv)
    return;

  for (argc = 0; argv[argc] != NULL; ++argc)
    free (argv[argc]);
  free (argv);
}

void
free_stringslen (char **argv, size_t len)
{
  size_t i;

  if (!argv)
    return;

  for (i = 0; i < len; ++i)
    free (argv[i]);
  free (argv);
}

/**
 * Compare device names (including partition numbers if present).
 *
 * L<https://rwmj.wordpress.com/2011/01/09/how-are-linux-drives-named-beyond-drive-26-devsdz/>
 */
int
compare_device_names (const char *a, const char *b)
{
  size_t alen, blen;
  int r;
  int a_partnum, b_partnum;

  /* Skip /dev/ prefix if present. */
  if (STRPREFIX (a, "/dev/"))
    a += 5;
  if (STRPREFIX (b, "/dev/"))
    b += 5;

  /* Skip sd/hd/ubd/vd. */
  alen = strcspn (a, "d");
  blen = strcspn (b, "d");
  assert (alen > 0 && alen <= 2);
  assert (blen > 0 && blen <= 2);
  a += alen + 1;
  b += blen + 1;

  /* Get device name part, that is, just 'a', 'ab' etc. */
  alen = strcspn (a, "0123456789");
  blen = strcspn (b, "0123456789");

  /* If device name part is longer, it is always greater, eg.
   * "/dev/sdz" < "/dev/sdaa".
   */
  if (alen != blen)
    return alen - blen;

  /* Device name parts are the same length, so do a regular compare. */
  r = strncmp (a, b, alen);
  if (r != 0)
    return r;

  /* Compare partitions numbers. */
  a += alen;
  b += alen;

  /* If no partition numbers, bail -- the devices are the same.  This
   * can happen in one peculiar case: where you have a mix of devices
   * with different interfaces (eg. /dev/sda and /dev/vda).
   * (RHBZ#858128).
   */
  if (!*a && !*b)
    return 0;

  r = sscanf (a, "%d", &a_partnum);
  assert (r == 1);
  r = sscanf (b, "%d", &b_partnum);
  assert (r == 1);

  return a_partnum - b_partnum;
}

static int
compare_device_names_vp (const void *vp1, const void *vp2)
{
  char * const *p1 = (char * const *) vp1;
  char * const *p2 = (char * const *) vp2;
  return compare_device_names (*p1, *p2);
}

void
sort_device_names (char **argv, size_t len)
{
  qsort (argv, len, sizeof (char *), compare_device_names_vp);
}

char *
concat_strings (char *const *argv)
{
  return join_strings ("", argv);
}

char *
join_strings (const char *separator, char *const *argv)
{
  size_t i, len, seplen, rlen;
  char *r;

  seplen = strlen (separator);

  len = 0;
  for (i = 0; argv[i] != NULL; ++i) {
    if (i > 0)
      len += seplen;
    len += strlen (argv[i]);
  }
  len++; /* for final \0 */

  r = malloc (len);
  if (r == NULL)
    return NULL;

  rlen = 0;
  for (i = 0; argv[i] != NULL; ++i) {
    if (i > 0) {
      memcpy (&r[rlen], separator, seplen);
      rlen += seplen;
    }
    len = strlen (argv[i]);
    memcpy (&r[rlen], argv[i], len);
    rlen += len;
  }
  r[rlen] = '\0';

  return r;
}

/**
 * Split an output string into a NULL-terminated list of lines,
 * wrapped into a stringsbuf.
 *
 * Typically this is used where we have run an external command
 * which has printed out a list of things, and we want to return
 * an actual list.
 *
 * The corner cases here are quite tricky.  Note in particular:
 *
 * =over 4
 *
 * =item C<"">
 *
 * returns C<[]>
 *
 * =item C<"\n">
 *
 * returns C<[""]>
 *
 * =item C<"a\nb">
 *
 * returns C<["a"; "b"]>
 *
 * =item C<"a\nb\n">
 *
 * returns C<["a"; "b"]>
 *
 * =item C<"a\nb\n\n">
 *
 * returns C<["a"; "b"; ""]>
 *
 * =back
 *
 * The original string is written over and destroyed by this function
 * (which is usually OK because it's the 'out' string from
 * C<command*()>).  You can free the original string, because
 * C<add_string()> strdups the strings.
 *
 * C<argv> in the C<struct stringsbuf> will be C<NULL> in case of errors.
 */
struct stringsbuf
split_lines_sb (char *str)
{
  DECLARE_STRINGSBUF (lines);
  DECLARE_STRINGSBUF (null);
  char *p, *pend;

  if (STREQ (str, "")) {
    /* No need to check the return value, as the stringsbuf will be
     * returned as it is anyway.
     */
    end_stringsbuf (&lines);
    return lines;
  }

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

    if (add_string (&lines, p) == -1) {
      free_stringsbuf (&lines);
      return null;
    }

    p = pend;
  }

  if (end_stringsbuf (&lines) == -1) {
    free_stringsbuf (&lines);
    return null;
  }

  return lines;
}

char **
split_lines (char *str)
{
  struct stringsbuf sb = split_lines_sb (str);
  return take_stringsbuf (&sb);
}

char **
empty_list (void)
{
  DECLARE_STRINGSBUF (ret);

  if (end_stringsbuf (&ret) == -1)
    return NULL;

  return ret.argv;
}

/**
 * Skip leading and trailing whitespace, updating the original string
 * in-place.
 */
void
trim (char *str)
{
  size_t len = strlen (str);

  while (len > 0 && c_isspace (str[len-1])) {
    str[len-1] = '\0';
    len--;
  }

  const char *p = str;
  while (*p && c_isspace (*p)) {
    p++;
    len--;
  }

  memmove (str, p, len+1);
}

/**
 * printf helper function so we can use C<%Q> ("quoted") and C<%R> to
 * print shell-quoted strings.  See L<guestfs-hacking(1)> for more
 * details.
 */
static int
print_shell_quote (FILE *stream,
                   const struct printf_info *info ATTRIBUTE_UNUSED,
                   const void *const *args)
{
#define SAFE(c) (c_isalnum((c)) ||					\
                 (c) == '/' || (c) == '-' || (c) == '_' || (c) == '.')
  int i, len;
  const char *str = *((const char **) (args[0]));

  for (i = len = 0; str[i]; ++i) {
    if (!SAFE (str[i])) {
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

/**
 * Parse the mountable descriptor for a btrfs subvolume.  Don't call
 * this directly; it is only used from the stubs.
 *
 * A btrfs subvolume is given as:
 *
 *  btrfsvol:/dev/sda3/root
 *
 * where F</dev/sda3> is a block device containing a btrfs filesystem,
 * and root is the name of a subvolume on it. This function is passed
 * the string following C<"btrfsvol:">.
 *
 * On success, C<mountable-E<gt>device> and C<mountable-E<gt>volume>
 * must be freed by the caller.
 */
int
parse_btrfsvol (const char *desc_orig, mountable_t *mountable)
{
  CLEANUP_FREE char *desc = NULL;
  CLEANUP_FREE char *device = NULL;
  const char *volume = NULL;
  char *slash;
  struct stat statbuf;

  mountable->type = MOUNTABLE_BTRFSVOL;

  if (!STRPREFIX (desc_orig, "/dev/"))
    return -1;

  desc = strdup (desc_orig);
  if (desc == NULL) {
    perror ("strdup");
    return -1;
  }

  slash = desc + strlen ("/dev/") - 1;
  while ((slash = strchr (slash + 1, '/'))) {
    *slash = '\0';

    free (device);
    device = device_name_translation (desc);
    if (!device) {
      perror (desc);
      continue;
    }

    if (stat (device, &statbuf) == -1) {
      perror (device);
      return -1;
    }

    if (!S_ISDIR (statbuf.st_mode) &&
        !is_root_device_stat (&statbuf)) {
      volume = slash + 1;
      break;
    }

    *slash = '/';
  }

  if (!device) return -1;

  if (!volume) return -1;

  mountable->volume = strdup (volume);
  if (!mountable->volume) {
    perror ("strdup");
    return -1;
  }

  mountable->device = device;
  device = NULL; /* to stop CLEANUP_FREE from freeing it */

  return 0;
}

/**
 * Convert a C<mountable_t> back to its string representation
 *
 * This function can be used in an error path, so must not call
 * C<reply_with_error>.
 */
char *
mountable_to_string (const mountable_t *mountable)
{
  char *desc;

  switch (mountable->type) {
  case MOUNTABLE_DEVICE:
  case MOUNTABLE_PATH:
    return strdup (mountable->device);

  case MOUNTABLE_BTRFSVOL:
    if (asprintf (&desc, "btrfsvol:%s/%s",
		  mountable->device, mountable->volume) == -1)
      return NULL;
    return desc;

  default:
    return NULL;
  }
}

#if defined(__GNUC__) && GUESTFS_GCC_VERSION >= 40800 /* gcc >= 4.8.0 */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wstack-usage="
#endif

/**
 * Check program exists and is executable on C<$PATH>.
 */
int
prog_exists (const char *prog)
{
  const char *pathc = getenv ("PATH");

  if (!pathc)
    return 0;

  const size_t proglen = strlen (prog);
  const char *elem;
  char *saveptr;
  const size_t len = strlen (pathc) + 1;
  char path[len];
  strcpy (path, pathc);

  elem = strtok_r (path, ":", &saveptr);
  while (elem) {
    const size_t n = strlen (elem) + proglen + 2;
    char testprog[n];

    snprintf (testprog, n, "%s/%s", elem, prog);
    if (access (testprog, X_OK) == 0)
      return 1;

    elem = strtok_r (NULL, ":", &saveptr);
  }

  /* Not found. */
  return 0;
}

#if defined(__GNUC__) && GUESTFS_GCC_VERSION >= 40800 /* gcc >= 4.8.0 */
#pragma GCC diagnostic pop
#endif

/**
 * Pass a template such as C<"/sysroot/XXXXXXXX.XXX">.  This updates
 * the template to contain a randomly named file.  Any C<'X'>
 * characters after the final C<'/'> in the template are replaced with
 * random characters.
 *
 * Notes: You should probably use an 8.3 path, so it's compatible with
 * all filesystems including basic FAT.  Also this only substitutes
 * lowercase ASCII letters and numbers, again for compatibility with
 * lowest common denominator filesystems.
 *
 * This doesn't create a file or check whether or not the file exists
 * (it would be extremely unlikely to exist as long as the RNG is
 * working).
 *
 * If there is an error, C<-1> is returned.
 */
int
random_name (char *template)
{
  int fd;
  unsigned char c;
  char *p;

  fd = open ("/dev/urandom", O_RDONLY|O_CLOEXEC);
  if (fd == -1)
    return -1;

  p = strrchr (template, '/');
  if (p == NULL)
    abort ();                   /* internal error - bad template */

  while (*p) {
    if (*p == 'X') {
      if (read (fd, &c, 1) != 1) {
        close (fd);
        return -1;
      }
      *p = "0123456789abcdefghijklmnopqrstuvwxyz"[c % 36];
    }

    p++;
  }

  close (fd);
  return 0;
}

/**
 * LVM and other commands aren't synchronous, especially when udev is
 * involved.  eg. You can create or remove some device, but the
 * C</dev> device node won't appear until some time later.  This means
 * that you get an error if you run one command followed by another.
 *
 * Use C<udevadm settle> after certain commands, but don't be too
 * fussed if it fails.
 */
void
udev_settle_file (const char *file)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  CLEANUP_FREE char *err = NULL;
  size_t i = 0;
  int r;

  ADD_ARG (argv, i, str_udevadm);
  if (verbose)
    ADD_ARG (argv, i, "--debug");

  ADD_ARG (argv, i, "settle");
  if (file) {
    ADD_ARG (argv, i, "-E");
    ADD_ARG (argv, i, file);
  }
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1)
    fprintf (stderr, "udevadm settle: %s\n", err);
}

void
udev_settle (void)
{
  udev_settle_file (NULL);
}

char *
get_random_uuid (void)
{
  int r;
  char *out;
  CLEANUP_FREE char *err = NULL;

  r = command (&out, &err, str_uuidgen, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return NULL;
  }

  /* caller free */
  return out;

}

/**
 * Turn list C<excludes> into a temporary file, and return a string
 * containing the temporary file name.  Caller must unlink the file
 * and free the string.
 *
 * C<function> is the function that invoked this helper, and it is
 * used mainly for errors/debugging.
 */
char *
make_exclude_from_file (const char *function, char *const *excludes)
{
  size_t i;
  int fd;
  char template[] = "/tmp/excludesXXXXXX";
  char *ret;

  fd = mkstemp (template);
  if (fd == -1) {
    reply_with_perror ("mkstemp");
    return NULL;
  }

  for (i = 0; excludes[i] != NULL; ++i) {
    if (strchr (excludes[i], '\n')) {
      reply_with_error ("%s: excludes file patterns cannot contain \\n character",
                        function);
      goto error;
    }

    if (xwrite (fd, excludes[i], strlen (excludes[i])) == -1 ||
        xwrite (fd, "\n", 1) == -1) {
      reply_with_perror ("write");
      goto error;
    }

    if (verbose)
      fprintf (stderr, "%s: adding excludes pattern '%s'\n",
               function, excludes[i]);
  }

  if (close (fd) == -1) {
    reply_with_perror ("close");
    fd = -1;
    goto error;
  }
  fd = -1;

  ret = strdup (template);
  if (ret == NULL) {
    reply_with_perror ("strdup");
    goto error;
  }

  return ret;

 error:
  if (fd >= 0)
    close (fd);
  unlink (template);
  return NULL;
}

void
cleanup_free_mountable (mountable_t *mountable)
{
  if (mountable) {
    free (mountable->device);
    free (mountable->volume);
  }
}
