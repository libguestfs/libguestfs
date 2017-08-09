/* This is a more significant example of a tool which can grab the
 * DHCP address from some types of virtual machine.  Since there are
 * so many possible ways to do this, without clarity on which is the
 * best way, I don't want to make this into an official virt tool.
 *
 * For more information, see:
 *
 * https://rwmj.wordpress.com/2010/10/26/tip-find-the-ip-address-of-a-virtual-machine/
 * https://rwmj.wordpress.com/2011/03/30/tip-another-way-to-get-the-ip-address-of-a-virtual-machine/
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <assert.h>

#include <guestfs.h>

static int compare_keys_len (const void *p1, const void *p2);
static size_t count_strings (char *const *argv);
static void free_strings (char **argv);
static void mount_disks (guestfs_h *g, char *root);
static void print_dhcp_address (guestfs_h *g, char *root);
static void print_dhcp_address_linux (guestfs_h *g, char *root, const char *logfile);
static void print_dhcp_address_windows (guestfs_h *g, char *root);

int
main (int argc, char *argv[])
{
  guestfs_h *g;
  size_t i;
  char **roots, *root;

  if (argc < 2) {
    fprintf (stderr,
             "Usage: virt-dhcp-address disk.img [disk.img [...]]\n"
             "Note that all disks must come from a single virtual machine.\n");
    exit (EXIT_FAILURE);
  }

  g = guestfs_create ();
  if (g == NULL) {
    perror ("failed to create libguestfs handle");
    exit (EXIT_FAILURE);
  }

  for (i = 1; i < (size_t) argc; ++i) {
    /* Attach the disk image(s) read-only to libguestfs. */
    if (guestfs_add_drive_opts (g, argv[i],
                                /* GUESTFS_ADD_DRIVE_OPTS_FORMAT, "raw", */
                                GUESTFS_ADD_DRIVE_OPTS_READONLY, 1,
                                -1) /* this marks end of optional arguments */
        == -1)
      exit (EXIT_FAILURE);
  }

  /* Run the libguestfs back-end. */
  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  /* Ask libguestfs to inspect for operating systems. */
  roots = guestfs_inspect_os (g);
  if (roots == NULL)
    exit (EXIT_FAILURE);
  if (roots[0] == NULL) {
    fprintf (stderr, "virt-dhcp-address: no operating systems found\n");
    exit (EXIT_FAILURE);
  }
  if (count_strings (roots) > 1) {
    fprintf (stderr, "virt-dhcp-address: multi-boot operating system\n");
    exit (EXIT_FAILURE);
  }

  root = roots[0];

  /* Mount up the guest's disks. */
  mount_disks (g, root);

  /* Print DHCP address. */
  print_dhcp_address (g, root);

  /* Close handle and exit. */
  guestfs_close (g);
  free_strings (roots);

  exit (EXIT_SUCCESS);
}

static void
mount_disks (guestfs_h *g, char *root)
{
  char **mountpoints;
  size_t i;

  /* Mount up the disks, like guestfish -i.
   *
   * Sort keys by length, shortest first, so that we end up
   * mounting the filesystems in the correct order.
   */
  mountpoints = guestfs_inspect_get_mountpoints (g, root);
  if (mountpoints == NULL)
    exit (EXIT_FAILURE);

  qsort (mountpoints, count_strings (mountpoints) / 2, 2 * sizeof (char *),
         compare_keys_len);

  for (i = 0; mountpoints[i] != NULL; i += 2) {
    /* Ignore failures from this call, since bogus entries can
     * appear in the guest's /etc/fstab.
     */
    guestfs_mount_ro (g, mountpoints[i+1], mountpoints[i]);
  }

  free_strings (mountpoints);
}

static void
print_dhcp_address (guestfs_h *g, char *root)
{
  char *guest_type, *guest_distro;

  /* Depending on the guest type, try to get the DHCP address. */
  guest_type = guestfs_inspect_get_type (g, root);
  if (guest_type == NULL)
    exit (EXIT_FAILURE);

  if (strcmp (guest_type, "linux") == 0) {
    guest_distro = guestfs_inspect_get_distro (g, root);
    if (guest_distro == NULL)
      exit (EXIT_FAILURE);

    if (strcmp (guest_distro, "fedora") == 0 ||
        strcmp (guest_distro, "rhel") == 0 ||
        strcmp (guest_distro, "redhat-based") == 0) {
      print_dhcp_address_linux (g, root, "/var/log/messages");
    }
    else if (strcmp (guest_distro, "debian") == 0 ||
             strcmp (guest_distro, "ubuntu") == 0) {
      print_dhcp_address_linux (g, root, "/var/log/syslog");
    }
    else {
      fprintf (stderr, "virt-dhcp-address: don't know how to get DHCP address from '%s'\n",
               guest_distro);
      exit (EXIT_FAILURE);
    }

    free (guest_distro);
  }
  else if (strcmp (guest_type, "windows") == 0) {
    print_dhcp_address_windows (g, root);
  }
  else {
    fprintf (stderr, "virt-dhcp-address: don't know how to get DHCP address from '%s'\n",
             guest_type);
    exit (EXIT_FAILURE);
  }

  free (guest_type);
}

/* Look for dhclient messages in logfile.
 */
static void
print_dhcp_address_linux (guestfs_h *g, char *root, const char *logfile)
{
  char **lines, *p;
  size_t len;

  lines = guestfs_grep_opts (g, "dhclient.*: bound to ", logfile,
                             GUESTFS_GREP_OPTS_EXTENDED, 1,
                             -1);
  if (lines == NULL)
    exit (EXIT_FAILURE);

  len = count_strings (lines);
  if (len == 0) {
    fprintf (stderr, "virt-dhcp-address: cannot find DHCP address for this guest.\n");
    exit (EXIT_FAILURE);
  }

  /* Only want the last message. */
  p = strstr (lines[len-1], "bound to ");
  assert (p);
  p += 9;
  len = strcspn (p, " ");
  p[len] = '\0';

  printf ("%s\n", p);

  free_strings (lines);
}

/* Download the Windows SYSTEM hive and find DHCP configuration in there. */
static void
print_dhcp_address_windows (guestfs_h *g, char *root_fs)
{
  char *system_path;
  int64_t root, node, value;
  struct guestfs_hivex_node_list *nodes;
  char *controlset;
  size_t i;
  char *p;

  /* Locate the SYSTEM hive. */
  system_path = guestfs_inspect_get_windows_system_hive (g, root_fs);
  if (!system_path)
    exit (EXIT_FAILURE);

  /* Open the hive to parse it.  Note that before libguestfs 1.19.35
   * you had to download the file and parse it using hivex(3).  Since
   * libguestfs 1.19.35, parts of the hivex(3) API are now exposed
   * through libguestfs, and that is what we'll use here because it is
   * more convenient and avoids having to download the hive.
   */
  if (guestfs_hivex_open (g, system_path, -1) == -1)
    exit (EXIT_FAILURE);

  free (system_path);

  root = guestfs_hivex_root (g);
  if (root == -1)
    exit (EXIT_FAILURE);

  /* Get ControlSetXXX\Services\Tcpip\Parameters\Interfaces. */
  controlset = guestfs_inspect_get_windows_current_control_set (g, root_fs);
  if (controlset == NULL)
    exit (EXIT_FAILURE);
  const char *path[] = { controlset, "Services", "Tcpip", "Parameters",
                         "Interfaces" };
  node = root;
  for (i = 0; node > 0 && i < sizeof path / sizeof path[0]; ++i)
    node = guestfs_hivex_node_get_child (g, node, path[i]);

  if (node == -1)
    exit (EXIT_FAILURE);

  if (node == 0) {
    fprintf (stderr, "virt-dhcp-address: HKLM\\System\\%s\\Services\\Tcpip\\Parameters\\Interfaces not found.", controlset);
    exit (EXIT_FAILURE);
  }

  free (controlset);

  /* Look for a node under here which has a "DhcpIPAddress" entry in it. */
  nodes = guestfs_hivex_node_children (g, node);
  if (nodes == NULL)
    exit (EXIT_FAILURE);

  value = 0;
  for (i = 0; value == 0 && i < nodes->len; ++i) {
    value = guestfs_hivex_node_get_value (g, nodes->val[i].hivex_node_h,
                                          "DhcpIPAddress");
    if (value == -1)
      exit (EXIT_FAILURE);
  }

  if (value == 0) {
    fprintf (stderr, "virt-dhcp-address: cannot find DHCP address for this guest.\n");
    exit (EXIT_FAILURE);
  }

  guestfs_free_hivex_node_list (nodes);

  /* Get the string and use libguestfs's auto-conversion to convert it
   * to UTF-8 for output.
   */
  p = guestfs_hivex_value_string (g, value);
  if (!p)
    exit (EXIT_FAILURE);

  printf ("%s\n", p);

  free (p);

  /* Close the hive handle. */
  guestfs_hivex_close (g);
}

static int
compare_keys_len (const void *p1, const void *p2)
{
  const char *key1 = * (char * const *) p1;
  const char *key2 = * (char * const *) p2;
  return strlen (key1) - strlen (key2);
}

static size_t
count_strings (char *const *argv)
{
  size_t c;

  for (c = 0; argv[c]; ++c)
    ;
  return c;
}

static void
free_strings (char **argv)
{
  size_t i;

  for (i = 0; argv[i]; ++i)
    free (argv[i]);
  free (argv);
}
