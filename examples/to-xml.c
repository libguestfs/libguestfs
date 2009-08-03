/* This inspects a block device and produces an XML representation of
 * the partitions, LVM, filesystems that we find there.  This could be
 * useful as example code of how to do this sort of probing, or to
 * feed the XML to other programs.
 *
 * Usage:
 *   to-xml guest.img [guest.img ...]
 */

#if HAVE_CONFIG_H
# include <config.h>
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <inttypes.h>
#include <unistd.h>
#include <ctype.h>

#include <guestfs.h>

/* Note that if any API call fails, we can just exit.  The
 * standard error handler will have printed the error message
 * to stderr already.
 */
#define CALL(call,errcode)			\
  if ((call) == (errcode)) exit (1);

static void display_partition (guestfs_h *g, const char *dev);
static void display_partitions (guestfs_h *g, const char *dev);
static void display_ext234 (guestfs_h *g, const char *dev, const char *fstype);

int
main (int argc, char *argv[])
{
  guestfs_h *g;
  int i;

  if (argc < 2 || access (argv[1], F_OK) != 0) {
    fprintf (stderr, "Usage: to-xml guest.img [guest.img ...]\n");
    exit (1);
  }

  if (!(g = guestfs_create ())) {
    fprintf (stderr, "Cannot create libguestfs handle.\n");
    exit (1);
  }

  for (i = 1; i < argc; ++i)
    CALL (guestfs_add_drive (g, argv[i]), -1);

  CALL (guestfs_launch (g), -1);
  CALL (guestfs_wait_ready (g), -1);

  printf ("<guestfs-system>\n");

  /* list-devices should return the devices that we just attached?
   * Better to find out what the kernel thinks are devices anyway ...
   */
  char **devices;
  CALL (devices = guestfs_list_devices (g), NULL);
  printf ("<devices>\n");
  for (i = 0; devices[i] != NULL; ++i) {
    int64_t size;
    CALL (size = guestfs_blockdev_getsize64 (g, devices[i]), -1);
    printf ("<device dev=\"%s\" size=\"%" PRIi64 "\">\n", devices[i], size);
    display_partitions (g, devices[i]);
    free (devices[i]);
    printf ("</device>\n");
  }
  free (devices);
  printf ("</devices>\n");

  /* Now do the same for VGs and LVs.  Note that a VG may span
   * multiple PVs / block devices, in arbitrary ways, which is
   * why VGs are in a separate top-level XML class.
   */
  char **vgs;
  char **lvs;
  printf ("<volgroups>\n");
  CALL (vgs = guestfs_vgs (g), NULL);
  CALL (lvs = guestfs_lvs (g), NULL);
  for (i = 0; vgs[i] != NULL; ++i) {
    printf ("<volgroup name=\"%s\">\n", vgs[i]);

    /* Just the LVs in this VG. */
    int len = strlen (vgs[i]);
    int j;
    for (j = 0; lvs[j] != NULL; ++j) {
      if (strncmp (lvs[j], "/dev/", 5) == 0 &&
          strncmp (&lvs[j][5], vgs[i], len) == 0 &&
          lvs[j][len+5] == '/') {
        int64_t size;
        CALL (size = guestfs_blockdev_getsize64 (g, lvs[j]), -1);
        printf ("<logvol name=\"%s\" size=\"%" PRIi64 "\">\n", lvs[j], size);
        display_partition (g, lvs[j]);
        printf ("</logvol>\n");
        free (lvs[j]);
      }
    }

    free (vgs[i]);
    printf ("</volgroup>\n");
  }
  free (vgs);
  free (lvs);
  printf ("</volgroups>\n");

  guestfs_close (g);
  printf ("</guestfs-system>\n");

  return 0;
}

/* Display a partition or LV. */
static void
display_partition (guestfs_h *g, const char *dev)
{
  char *what;

  CALL (what = guestfs_file (g, dev), NULL);

  if (strcmp (what, "x86 boot sector") == 0)
    /* This is what 'file' program shows for Windows/NTFS partitions. */
    printf ("<windows/>\n");
  else if (strstr (what, "boot sector") != NULL)
    display_partitions (g, dev);
  else if (strncmp (what, "LVM2", 4) == 0)
    printf ("<physvol/>\n");
  else if (strstr (what, "ext2 filesystem data") != NULL)
    display_ext234 (g, dev, "ext2");
  else if (strstr (what, "ext3 filesystem data") != NULL)
    display_ext234 (g, dev, "ext3");
  else if (strstr (what, "ext4 filesystem data") != NULL)
    display_ext234 (g, dev, "ext4");
  else if (strstr (what, "Linux/i386 swap file") != NULL)
    printf ("<linux-swap/>\n");
  else
    printf ("<unknown/>\n");

  free (what);
}

/* Display an MBR-formatted boot sector. */
static void
display_partitions (guestfs_h *g, const char *dev)
{
  /* We can't look into a boot sector which is an LV or partition.
   * That's a limitation of sorts of the Linux kernel.  (Actually,
   * we could do this if we add the kpartx program to libguestfs).
   */
  if (strncmp (dev, "/dev/sd", 7) != 0 || isdigit (dev[strlen(dev)-1])) {
    printf ("<vm-image dev=\"%s\"/>\n", dev);
    return;
  }

  char **parts;
  int i, len;
  CALL (parts = guestfs_list_partitions (g), NULL);
  printf ("<partitions>\n");

  len = strlen (dev);
  for (i = 0; parts[i] != NULL; ++i) {
    /* Only display partition if it's in the device. */
    if (strncmp (parts[i], dev, len) == 0) {
      int64_t size;
      CALL (size = guestfs_blockdev_getsize64 (g, parts[i]), -1);
      printf ("<partition dev=\"%s\" size=\"%" PRIi64 "\">\n", parts[i], size);
      display_partition (g, parts[i]);
      printf ("</partition>\n");
    }

    free (parts[i]);
  }
  free (parts);
  printf ("</partitions>\n");
}

/* Display some details on the ext2/3/4 filesystem on dev. */
static void
display_ext234 (guestfs_h *g, const char *dev, const char *fstype)
{
  char **sbfields;
  int i;

  printf ("<fs type=\"%s\">\n", fstype);
  CALL (sbfields = guestfs_tune2fs_l (g, dev), NULL);

  for (i = 0; sbfields[i] != NULL; i += 2) {
    /* Just pick out a few important fields to display.  There
     * is much more that could be displayed here.
     */
    if (strcmp (sbfields[i], "Filesystem UUID") == 0)
      printf ("<uuid>%s</uuid>\n", sbfields[i+1]);
    else if (strcmp (sbfields[i], "Block size") == 0)
      printf ("<blocksize>%s</blocksize>\n", sbfields[i+1]);

    free (sbfields[i]);
    free (sbfields[i+1]);
  }
  free (sbfields);

  printf ("</fs>\n");
}
