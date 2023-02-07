/* Test FUSE.
 * Copyright (C) 2009-2023 Red Hat Inc.
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

/* This used to be a shell script test, but using C gives us finer
 * control over exactly which system calls are being used, as well as
 * allowing us to avoid one launch of the appliance during the test.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <errno.h>
#include <error.h>

#ifdef HAVE_ACL
#include <sys/acl.h>
#include <acl/libacl.h>
#endif

#ifdef HAVE_SYS_XATTR_H
#include <sys/xattr.h>
#endif

#include <guestfs.h>
#include "guestfs-utils.h"

#include "ignore-value.h"

static guestfs_h *g;

#define SIZE INT64_C(1024*1024*1024)

/* NB: Must be a path that does not need quoting. */
static char mountpoint[] = "/tmp/testfuseXXXXXX";

static int acl_available;
static int linuxxattrs_available;

static void create_initial_filesystem (void);
static int test_fuse (void);

int
main (int argc, char *argv[])
{
  const char *s;
  const char *acl_group[] = { "acl", NULL };
  const char *linuxxattrs_group[] = { "linuxxattrs", NULL };
  int debug_calls, r, res;
  pid_t pid;
  struct sigaction sa;
  char cmd[128];

  /* Allow the test to be skipped.  Note I'm using the old shell
   * script name here.
   */
  s = getenv ("SKIP_TEST_FUSE_SH");
  if (s && STRNEQ (s, "")) {
    printf ("%s: test skipped because environment variable is set\n",
            argv[0]);
    exit (77);
  }

  if (access ("/dev/fuse", W_OK) == -1)
    error (77, errno, "access: /dev/fuse");

  g = guestfs_create ();
  if (g == NULL)
    error (EXIT_FAILURE, errno, "guestfs_create");

  if (guestfs_add_drive_scratch (g, SIZE, -1) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  /* Test features. */
  acl_available = guestfs_feature_available (g, (char **) acl_group);
  if (acl_available == -1) exit (EXIT_FAILURE);

  linuxxattrs_available =
    guestfs_feature_available (g, (char **) linuxxattrs_group);
  if (linuxxattrs_available == -1) exit (EXIT_FAILURE);

  create_initial_filesystem ();

  /* Make a mountpoint. */
  if (mkdtemp (mountpoint) == NULL)
    exit (EXIT_FAILURE);

  /* Mount the filesystem on the host using FUSE. */
  debug_calls = guestfs_get_trace (g);
  if (guestfs_mount_local (g, mountpoint,
                           GUESTFS_MOUNT_LOCAL_DEBUGCALLS, debug_calls,
                           -1) == -1)
    exit (EXIT_FAILURE);

  /* Fork to run the next part of the test. */
  pid = fork ();
  if (pid == -1)
    error (EXIT_FAILURE, errno, "fork");

  if (pid == 0) {               /* Child. */
    /* Move into the mountpoint for the tests. */
    if (chdir (mountpoint) == -1) {
      perror (mountpoint);
      _exit (EXIT_FAILURE);
    }

    res = test_fuse ();
    printf ("test_fuse() returned %d\n", res);
    fflush (stdout);

    /* Move out of the mountpoint (otherwise our cwd will prevent the
     * mountpoint from being unmounted below).
     */
    ignore_value (chdir ("/"));

    /* Who's using the mountpoint?  Should be no one. */
    snprintf (cmd, sizeof cmd, "%s %s", FUSER, mountpoint);
    printf ("%s\n", cmd);
    fflush (stdout);
    ignore_value (system (cmd));

    /* Unmount it. */
    snprintf (cmd, sizeof cmd, "guestunmount %s", mountpoint);
    printf ("%s\n", cmd);
    fflush (stdout);
    r = system (cmd);
    if (!WIFEXITED (r) || WEXITSTATUS (r) != EXIT_SUCCESS)
      fprintf (stderr, "%s: warning: guestunmount command failed\n", argv[0]);

    _exit (res == 0 ? EXIT_SUCCESS : EXIT_FAILURE);
  }

  /* Parent. */

  /* Ignore signals in the parent while running the child. */
  memset (&sa, 0, sizeof sa);
  sa.sa_handler = SIG_IGN;
  sigaction (SIGINT, &sa, NULL);
  sigaction (SIGTERM, &sa, NULL);

  if (guestfs_mount_local_run (g) == -1)
    exit (EXIT_FAILURE);

  /* Clean up and exit. */
  if (waitpid (pid, &r, 0) == -1)
    error (EXIT_FAILURE, errno, "waitpid");

  if (rmdir (mountpoint) == -1)
    error (EXIT_FAILURE, errno, "rmdir: %s", mountpoint);

  if (guestfs_shutdown (g) == -1)
    exit (EXIT_FAILURE);

  guestfs_close (g);

  /* Did the child process fail? */
  exit (!WIFEXITED (r) || WEXITSTATUS (r) != 0 ? EXIT_FAILURE : EXIT_SUCCESS);
}

/* Create a filesystem with some initial content. */
static void
create_initial_filesystem (void)
{
  if (guestfs_part_disk (g, "/dev/sda", "mbr") == -1)
    exit (EXIT_FAILURE);

  /* Use ext4 because it supports modern features.  Use >= 256 byte
   * inodes because these support nanosecond timestamps.
   */
  if (guestfs_mkfs_opts (g, "ext4", "/dev/sda1",
                         GUESTFS_MKFS_OPTS_INODE, 256,
                         -1) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_mount_options (g, "acl,user_xattr", "/dev/sda1", "/") == -1)
    exit (EXIT_FAILURE);

  if (guestfs_write (g, "/hello.txt", "hello", 5) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_write (g, "/world.txt", "hello world", 11) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_touch (g, "/empty") == -1)
    exit (EXIT_FAILURE);

  if (linuxxattrs_available) {
    if (guestfs_touch (g, "/user_xattr") == -1)
      exit (EXIT_FAILURE);

    if (guestfs_setxattr (g, "user.test", "hello123", 8, "/user_xattr") == -1)
      exit (EXIT_FAILURE);
  }

  if (acl_available) {
    if (guestfs_touch (g, "/acl") == -1)
      exit (EXIT_FAILURE);

    if (guestfs_acl_set_file (g, "/acl", "access",
                              "u::rwx,u:500:r,g::rwx,m::rwx,o::r-x") == -1)
      exit (EXIT_FAILURE);
  }
}

/* Run FUSE tests.  Mountpoint is current directory. */
static int
test_fuse (void)
{
  int stage = 0;
#define STAGE(fs,...)                                   \
  printf ("%02d: " fs "\n", ++stage, ##__VA_ARGS__);    \
  fflush (stdout)
  FILE *fp;
  char *line = NULL;
  size_t len = 0;
  struct stat statbuf;
  char buf[128];
  ssize_t r;
  unsigned u, u1;
  int fd;
  struct timeval tv[2];
  struct timespec ts[2];
#ifdef HAVE_ACL
  acl_t acl;
  char *acl_text;
#endif

  STAGE ("checking initial files exist");

  if (access ("empty", F_OK) == -1) {
    perror ("access: empty");
    return -1;
  }
  if (access ("hello.txt", F_OK) == -1) {
    perror ("access: hello.txt");
    return -1;
  }
  if (access ("world.txt", F_OK) == -1) {
    perror ("access: world.txt");
    return -1;
  }

  STAGE ("checking initial files contain expected content");

  fp = fopen ("hello.txt", "r");
  if (fp == NULL) {
    perror ("open: hello.txt");
    fclose (fp);
    return -1;
  }
  if (getline (&line, &len, fp) == -1) {
    perror ("getline: hello.txt");
    fclose (fp);
    return -1;
  }
  if (STRNEQ (line, "hello")) {
    fprintf (stderr, "'hello.txt' does not contain expected content\n");
    fclose (fp);
    return -1;
  }
  fclose (fp);

  fp = fopen ("world.txt", "r");
  if (fp == NULL) {
    perror ("open: world.txt");
    fclose (fp);
    return -1;
  }
  if (getline (&line, &len, fp) == -1) {
    perror ("getline: world.txt");
    fclose (fp);
    return -1;
  }
  if (STRNEQ (line, "hello world")) {
    fprintf (stderr, "'world.txt' does not contain expected content\n");
    fclose (fp);
    return -1;
  }
  fclose (fp);

  STAGE ("checking file modes and sizes of initial content");

  if (stat ("empty", &statbuf) == -1) {
    perror ("stat: empty");
    return -1;
  }
  if ((statbuf.st_mode & 0777) != 0644) {
    fprintf (stderr, "'empty' has invalid mode (%o)\n", statbuf.st_mode);
    return -1;
  }
  if (statbuf.st_size != 0) {
    fprintf (stderr, "'empty' has invalid size (%d)\n", (int) statbuf.st_size);
    return -1;
  }

  if (stat ("hello.txt", &statbuf) == -1) {
    perror ("stat: hello.txt");
    return -1;
  }
  if ((statbuf.st_mode & 0777) != 0644) {
    fprintf (stderr, "'hello.txt' has invalid mode (%o)\n", statbuf.st_mode);
    return -1;
  }
  if (statbuf.st_size != 5) {
    fprintf (stderr, "'hello.txt' has invalid size (%d)\n",
             (int) statbuf.st_size);
    return -1;
  }

  if (stat ("world.txt", &statbuf) == -1) {
    perror ("stat: world.txt");
    return -1;
  }
  if ((statbuf.st_mode & 0777) != 0644) {
    fprintf (stderr, "'world.txt' has invalid mode (%o)\n", statbuf.st_mode);
    return -1;
  }
  if (statbuf.st_size != 11) {
    fprintf (stderr, "'world.txt' has invalid size (%d)\n",
             (int) statbuf.st_size);
    return -1;
  }

  STAGE ("checking unlink");

  fp = fopen ("new", "w");
  if (fp == NULL) {
    perror ("open: new");
    fclose (fp);
    return -1;
  }
  fclose (fp);

  if (unlink ("new") == -1) {
    perror ("unlink: new");
    return -1;
  }

  STAGE ("checking symbolic link");

  if (symlink ("hello.txt", "symlink") == -1) {
    perror ("symlink: hello.txt, symlink");
    return -1;
  }
  if (lstat ("symlink", &statbuf) == -1) {
    perror ("lstat: symlink");
    return -1;
  }
  if (!S_ISLNK (statbuf.st_mode)) {
    fprintf (stderr, "'symlink' is not a symlink (mode = %o)\n",
             statbuf.st_mode);
    return -1;
  }

  STAGE ("checking readlink");

  r = readlink ("symlink", buf, sizeof buf);
  if (r == -1) {
    perror ("readlink: symlink");
    return -1;
  }
  /* readlink return buffer is not \0-terminated, hence: */
  if (r != 9 || memcmp (buf, "hello.txt", r) != 0) {
    fprintf (stderr, "readlink on 'symlink' returned incorrect result\n");
    return -1;
  }

  STAGE ("checking hard link");

  if (stat ("hello.txt", &statbuf) == -1) {
    perror ("stat: hello.txt");
    return -1;
  }
  if (statbuf.st_nlink != 1) {
    fprintf (stderr, "nlink of 'hello.txt' was %d (expected 1)\n",
             (int) statbuf.st_nlink);
    return -1;
  }

  if (link ("hello.txt", "link") == -1) {
    perror ("link: hello.txt, link");
    return -1;
  }

  if (stat ("link", &statbuf) == -1) {
    perror ("stat: link");
    return -1;
  }
  if (statbuf.st_nlink != 2) {
    fprintf (stderr, "nlink of 'link' was %d (expected 2)\n",
             (int) statbuf.st_nlink);
    return -1;
  }

#if 0
  /* This fails because of caching.  The problem is that the linked file
   * ("hello.txt") is cached with a link count of 1.  unlink("link")
   * invalidates the cache for "link", but _not_ for "hello.txt" which
   * still has the now-incorrect cached value.  However there's not much
   * we can do about this since searching for all linked inodes of a file
   * is an O(n) operation.
   */
  if (stat ("hello.txt", &statbuf) == -1) {
    perror ("stat: hello.txt");
    return -1;
  }
  if (statbuf.st_nlink != 2) {
    fprintf (stderr, "nlink of 'hello.txt' was %d (expected 2)\n",
             (int) statbuf.st_nlink);
    return -1;
  }

  if (unlink ("link") == -1) {
    perror ("unlink: link");
    return -1;
  }

  if (stat ("hello.txt", &statbuf) == -1) {
    perror ("stat: hello.txt");
    return -1;
  }
  if (statbuf.st_nlink != 1) {
    fprintf (stderr, "nlink of 'hello.txt' was %d (expected 1)\n",
             (int) statbuf.st_nlink);
    return -1;
  }
#endif

  STAGE ("checking mkdir");

  if (mkdir ("newdir", 0755) == -1) {
    perror ("mkdir: newdir");
    return -1;
  }

  STAGE ("checking rmdir");

  if (rmdir ("newdir") == -1) {
    perror ("rmdir: newdir");
    return -1;
  }

  STAGE ("checking rename");

  fp = fopen ("old", "w");
  if (fp == NULL) {
    perror ("open: old");
    return -1;
  }
  fclose (fp);
  if (rename ("old", "new") == -1) {
    perror ("rename: old, new");
    return -1;
  }
  if (access ("new", F_OK) == -1) {
    perror ("access: new");
    return -1;
  }
  if (access ("old", F_OK) == 0) {
    fprintf (stderr, "file 'old' exists after rename\n");
    return -1;
  }
  if (unlink ("new") == -1) {
    perror ("unlink: new");
    return -1;
  }

  STAGE ("checking chmod");

  fp = fopen ("new", "w");
  if (fp == NULL) {
    perror ("open: new");
    return -1;
  }
  fclose (fp);
  for (u = 0; u < 0777; u += 0111) {
    if (chmod ("new", u) == -1) {
      perror ("chmod: new");
      return -1;
    }
    if (stat ("new", &statbuf) == -1) {
      perror ("stat: new");
      return -1;
    }
    if ((statbuf.st_mode & 0777) != u) {
      fprintf (stderr, "unexpected mode: was %o expected %o\n",
               statbuf.st_mode, u);
      return -1;
    }
  }
  if (unlink ("new") == -1) {
    perror ("unlink: new");
    return -1;
  }

  STAGE ("checking truncate");

  fp = fopen ("truncated", "w");
  if (fp == NULL) {
    perror ("open: truncated");
    return -1;
  }
  fclose (fp);
  for (u = 10000; u <= 10000; u -= 1000) {
    if (truncate ("truncated", u) == -1) {
      perror ("truncate");
      return -1;
    }
    if (stat ("truncated", &statbuf) == -1) {
      perror ("stat: truncated");
      return -1;
    }
    if (statbuf.st_size != u) {
      fprintf (stderr, "unexpected size: was %u expected %u\n",
               (unsigned) statbuf.st_size, u);
      return -1;
    }
  }
  if (unlink ("truncated") == -1) {
    perror ("unlink: truncated");
    return -1;
  }

  STAGE ("checking utimes");

  fd = open ("timestamp", O_WRONLY|O_CREAT|O_TRUNC|O_NOCTTY|O_CLOEXEC, 0644);
  if (fd == -1) {
    perror ("open: timestamp");
    return -1;
  }
  close (fd);
  tv[0].tv_sec = 23;            /* atime */
  tv[0].tv_usec = 45;
  tv[1].tv_sec = 67;            /* mtime */
  tv[1].tv_usec = 89;
  if (utimes ("timestamp", tv) == -1) {
    perror ("utimes: timestamp");
    return -1;
  }
  if (stat ("timestamp", &statbuf) == -1) {
    perror ("fstat: timestamp");
    return -1;
  }
  if (statbuf.st_atime != 23 ||
      statbuf.st_atim.tv_nsec != 45000 ||
      statbuf.st_mtime != 67 ||
      statbuf.st_mtim.tv_nsec != 89000) {
    fprintf (stderr, "utimes did not set time (%d/%d/%d/%d)\n",
             (int) statbuf.st_atime, (int) statbuf.st_atim.tv_nsec,
             (int) statbuf.st_mtime, (int) statbuf.st_mtim.tv_nsec);
    return -1;
  }

  STAGE ("checking utimens");

  fd = open ("timestamp", O_WRONLY|O_CREAT|O_TRUNC|O_NOCTTY|O_CLOEXEC, 0644);
  if (fd == -1) {
    perror ("open: timestamp");
    return -1;
  }
  ts[0].tv_sec = 12;            /* atime */
  ts[0].tv_nsec = 34;
  ts[1].tv_sec = 56;            /* mtime */
  ts[1].tv_nsec = 78;
  if (futimens (fd, ts) == -1) {
    perror ("futimens: timestamp");
    close (fd);
    return -1;
  }
  if (fstat (fd, &statbuf) == -1) {
    perror ("fstat: timestamp");
    close (fd);
    return -1;
  }
  if (statbuf.st_atime != 12 ||
      statbuf.st_atim.tv_nsec != 34 ||
      statbuf.st_mtime != 56 ||
      statbuf.st_mtim.tv_nsec != 78) {
    fprintf (stderr, "utimens did not set time (%d/%d/%d/%d)\n",
             (int) statbuf.st_atime, (int) statbuf.st_atim.tv_nsec,
             (int) statbuf.st_mtime, (int) statbuf.st_mtim.tv_nsec);
    close (fd);
    return -1;
  }
  close (fd);

  STAGE ("checking writes");

  fp = fopen ("new.txt", "w");
  if (fp == NULL) {
    perror ("open: new.txt");
    fclose (fp);
    return -1;
  }
  for (u = 0; u < 1000; ++u) {
    if (fprintf (fp, "line %u\n", u) == -1) {
      perror ("fprintf: new.txt");
      fclose (fp);
      return -1;
    }
  }
  if (fclose (fp) == -1) {
    perror ("fclose: new.txt");
    return -1;
  }

  fp = fopen ("new.txt", "r");
  if (fp == NULL) {
    perror ("open: new.txt");
    return -1;
  }
  for (u = 0; u < 1000; ++u) {
    if (getline (&line, &len, fp) == -1) {
      perror ("getline: new.txt");
      fclose (fp);
      return -1;
    }
    if (sscanf (line, "line %u", &u1) != 1 || u != u1) {
      fprintf (stderr, "unexpected content: %s\n", line);
      fclose (fp);
      return -1;
    }
  }
  fclose (fp);

#ifdef HAVE_ACL
  if (acl_available) {
    STAGE ("checking POSIX ACL read operation");

    acl = acl_get_file ("acl", ACL_TYPE_ACCESS);
    if (acl == (acl_t) NULL) {
      perror ("acl_get_file: acl");
      return -1;
    }
    acl_text = acl_to_any_text (acl, NULL, '\n', TEXT_SOME_EFFECTIVE | TEXT_NUMERIC_IDS);
    if (acl_text == NULL) {
      perror ("acl_to_any_text: acl");
      return -1;
    }
    if (STRNEQ (acl_text, "user::rwx\nuser:500:r--\ngroup::rwx\nmask::rwx\nother::r-x")) {
      fprintf (stderr, "unexpected acl: %s\n", acl_text);
      return -1;
    }
    acl_free (acl_text);
    acl_free (acl);
  }
#endif

#if HAVE_GETXATTR
  if (linuxxattrs_available) {
    STAGE ("checking extended attribute (xattr) read operation");

    r = getxattr ("user_xattr", "user.test", buf, sizeof buf);
    if (r == -1) {
      perror ("getxattr");
      return -1;
    }
    if (r != 8 || memcmp (buf, "hello123", r) != 0) {
      fprintf (stderr, "user.test xattr on file user_xattr was incorrect\n");
      return -1;
    }
  }
#endif

  /* XXX:
     These ones are not yet tested by the current program:
     - statfs/statvfs

     These ones cannot easily be tested by the current program, because
     this program doesn't run as root:
     - fsync
     - chown
     - mknod
  */

  free (line);
  return 0;
}
