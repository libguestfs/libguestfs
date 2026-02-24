#include <guestfs.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <limits.h>

/* Some platforms don't define PATH_MAX */
#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define OSREL_SUFFIX "/os-release"

/* Simple assertion helper */
static void
check (const char *expected, const char *actual)
{
  if (!actual) {
    fprintf (stderr, "FAIL: got NULL, expected %s\n", expected);
    exit (EXIT_FAILURE);
  }

  if (strcmp (expected, actual) != 0) {
    fprintf (stderr, "FAIL: expected '%s', got '%s'\n", expected, actual);
    exit (EXIT_FAILURE);
  }
}

/* Print libguestfs error and abort */
static void
die_g (guestfs_h *g, const char *msg)
{
  const char *err = guestfs_last_error (g);
  fprintf (stderr, "ERROR: %s: %s\n", msg, err ? err : "(no error message)");
  exit (EXIT_FAILURE);
}

/* Return 1 if virt-make-fs is available in PATH, 0 otherwise. */
static int
have_virt_make_fs (void)
{
  int r = system ("virt-make-fs --version >/dev/null 2>&1");
  return r == 0;
}

/* Run virt-make-fs, using $RUN wrapper if set (as in libguestfs tests). */
static int
run_virt_make_fs (const char *rootdir, const char *img)
{
  const char *run = getenv ("RUN");
  char cmd[PATH_MAX * 2];

  if (run && run[0]) {
    if (snprintf (cmd, sizeof cmd,
                  "%s virt-make-fs --type=ext4 --format=qcow2 '%s' '%s'",
                  run, rootdir, img) >= (int) sizeof cmd) {
      fprintf (stderr, "command string too long\n");
      exit (EXIT_FAILURE);
    }
  } else {
    if (snprintf (cmd, sizeof cmd,
                  "virt-make-fs --type=ext4 --format=qcow2 '%s' '%s'",
                  rootdir, img) >= (int) sizeof cmd) {
      fprintf (stderr, "command string too long\n");
      exit (EXIT_FAILURE);
    }
  }

  fprintf (stderr, "Creating test image with command: %s\n", cmd);
  return system (cmd);
}

/* Create a tiny Linux filesystem image with basic OS structure and /etc/os-release.
 * The caller must free(3) the returned string and unlink(2) the file.
 */
static char *
create_linux_image (const char *id, const char *pretty_name, const char *version_id)
{
  if (!have_virt_make_fs ()) {
    fprintf (stderr, "SKIP: virt-make-fs not available in PATH\n");
    exit (77); /* automake-style skip */
  }

  char tmpl[] = "/tmp/test-osinfo-XXXXXX";
  char *rootdir;
  char etcdir[PATH_MAX];
  char bindir[PATH_MAX];
  char sbindir[PATH_MAX];
  char osrel[PATH_MAX + sizeof (OSREL_SUFFIX)];
  char fstab[PATH_MAX];
  char shpath[PATH_MAX];
  char initpath[PATH_MAX];
  char img[PATH_MAX];

  rootdir = mkdtemp (tmpl);
  if (rootdir == NULL) {
    perror ("mkdtemp");
    exit (EXIT_FAILURE);
  }

  /* /etc */
  if (snprintf (etcdir, sizeof etcdir, "%s/etc", rootdir) >= (int) sizeof etcdir) {
    fprintf (stderr, "etcdir path too long\n");
    exit (EXIT_FAILURE);
  }
  if (mkdir (etcdir, 0700) == -1) {
    perror ("mkdir etc");
    exit (EXIT_FAILURE);
  }

  /* /bin */
  if (snprintf (bindir, sizeof bindir, "%s/bin", rootdir) >= (int) sizeof bindir) {
    fprintf (stderr, "bindir path too long\n");
    exit (EXIT_FAILURE);
  }
  if (mkdir (bindir, 0700) == -1) {
    perror ("mkdir bin");
    exit (EXIT_FAILURE);
  }

  /* /sbin */
  if (snprintf (sbindir, sizeof sbindir, "%s/sbin", rootdir) >= (int) sizeof sbindir) {
    fprintf (stderr, "sbindir path too long\n");
    exit (EXIT_FAILURE);
  }
  if (mkdir (sbindir, 0700) == -1) {
    perror ("mkdir sbin");
    exit (EXIT_FAILURE);
  }

  /* /etc/os-release */
  if (snprintf (osrel, sizeof osrel, "%s%s", etcdir, OSREL_SUFFIX) >= (int) sizeof osrel) {
    fprintf (stderr, "os-release path too long\n");
    exit (EXIT_FAILURE);
  }
  FILE *f = fopen (osrel, "w");
  if (!f) {
    perror ("fopen os-release");
    exit (EXIT_FAILURE);
  }
  fprintf (f,
           "NAME=\"%s\"\n"
           "ID=%s\n"
           "VERSION_ID=\"%s\"\n",
           pretty_name, id, version_id);
  fclose (f);

  /* /etc/fstab – minimal dummy */
  if (snprintf (fstab, sizeof fstab, "%s/fstab", etcdir) >= (int) sizeof fstab) {
    fprintf (stderr, "fstab path too long\n");
    exit (EXIT_FAILURE);
  }
  f = fopen (fstab, "w");
  if (!f) {
    perror ("fopen fstab");
    exit (EXIT_FAILURE);
  }
  fprintf (f, "none / tmpfs defaults 0 0\n");
  fclose (f);

  /* /bin/sh – dummy executable */
  if (snprintf (shpath, sizeof shpath, "%s/sh", bindir) >= (int) sizeof shpath) {
    fprintf (stderr, "sh path too long\n");
    exit (EXIT_FAILURE);
  }
  f = fopen (shpath, "w");
  if (!f) {
    perror ("fopen /bin/sh");
    exit (EXIT_FAILURE);
  }
  fprintf (f, "#!/bin/sh\nexit 0\n");
  fclose (f);
  chmod (shpath, 0755);

  /* /sbin/init – dummy executable */
  if (snprintf (initpath, sizeof initpath, "%s/init", sbindir) >= (int) sizeof initpath) {
    fprintf (stderr, "init path too long\n");
    exit (EXIT_FAILURE);
  }
  f = fopen (initpath, "w");
  if (!f) {
    perror ("fopen /sbin/init");
    exit (EXIT_FAILURE);
  }
  fprintf (f, "#!/bin/sh\nexit 0\n");
  fclose (f);
  chmod (initpath, 0755);

  /* Image path */
  if (snprintf (img, sizeof img, "%s.img", rootdir) >= (int) sizeof img) {
    fprintf (stderr, "image path too long\n");
    exit (EXIT_FAILURE);
  }

  /* Build qcow2 image from the temp root dir */
  int r = run_virt_make_fs (rootdir, img);
  if (r != 0) {
    fprintf (stderr, "virt-make-fs failed with status %d\n", r);
    exit (EXIT_FAILURE);
  }

  char *img_path = strdup (img);
  if (!img_path) {
    perror ("strdup");
    exit (EXIT_FAILURE);
  }

  fprintf (stderr, "Created temporary image for %s: %s\n", id, img_path);
  return img_path;
}

/* Generic runner for one image + expected osinfo */
static void
run_osinfo_test (const char *img, const char *expected)
{
  guestfs_h *g = guestfs_create ();
  if (!g) {
    fprintf (stderr, "cannot create handle\n");
    exit (EXIT_FAILURE);
  }

  guestfs_set_verbose (g, 1);
  guestfs_set_trace (g, 1);

  fprintf (stderr, "\n=== Testing image: %s ===\n", img);

  if (guestfs_add_drive (g, img) == -1)
    die_g (g, "guestfs_add_drive");
  if (guestfs_launch (g) == -1)
    die_g (g, "guestfs_launch");

  char **roots = guestfs_inspect_os (g);
  if (!roots || !roots[0]) {
    die_g (g, "guestfs_inspect_os returned no roots");
  }

  fprintf (stderr, "inspect_os roots:\n");
  for (size_t i = 0; roots[i] != NULL; ++i)
    fprintf (stderr, "  root[%zu] = %s\n", i, roots[i]);

  const char *root = roots[0];
  fprintf (stderr, "Using root: %s\n", root);

  char *type   = guestfs_inspect_get_type (g, root);
  char *distro = guestfs_inspect_get_distro (g, root);
  int   major  = guestfs_inspect_get_major_version (g, root);
  int   minor  = guestfs_inspect_get_minor_version (g, root);

  fprintf (stderr, "inspect_get_type          = %s\n", type   ? type   : "(null)");
  fprintf (stderr, "inspect_get_distro        = %s\n", distro ? distro : "(null)");
  fprintf (stderr, "inspect_get_major_version = %d\n", major);
  fprintf (stderr, "inspect_get_minor_version = %d\n", minor);

  char *info = guestfs_inspect_get_osinfo (g, root);

  /* Big, bold, highly visible OSINFO block */
  fprintf (stderr,
           "\n"
           "==============================================\n"
           "   \033[1mOSINFO RESULT\033[0m\n"
           "==============================================\n"
           "  \033[1m%s\033[0m\n"
           "==============================================\n\n",
           info ? info : "(null)");

  check (expected, info);

  free (info);
  free (type);
  free (distro);

  guestfs_close (g);
}

int
main (void)
{
  /* Ubuntu 22.04 -> ubuntu22.04 */
  char *ubuntu_img = create_linux_image ("ubuntu", "Ubuntu", "22.04");
  run_osinfo_test (ubuntu_img, "ubuntu22.04");
  if (unlink (ubuntu_img) == -1)
    perror ("unlink ubuntu image");
  free (ubuntu_img);

  /* Fedora 40 -> fedora40 (FORMAT_MAJOR_ONLY) */
  char *fedora_img = create_linux_image ("fedora", "Fedora Linux", "40");
  run_osinfo_test (fedora_img, "fedora40");
  if (unlink (fedora_img) == -1)
    perror ("unlink fedora image");
  free (fedora_img);

  /* Debian 12 -> debian12 (FORMAT_MAJOR_ONLY) */
  char *debian_img = create_linux_image ("debian", "Debian GNU/Linux", "12");
  run_osinfo_test (debian_img, "debian12");
  if (unlink (debian_img) == -1)
    perror ("unlink debian image");
  free (debian_img);

  fprintf (stderr, "\nAll Linux tests PASS\n");
  return EXIT_SUCCESS;
}
