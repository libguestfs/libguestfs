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
#include <hivex.h>

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

  lines = guestfs_egrep (g, "dhclient.*: bound to ", logfile);
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
  char tmpfile[] = "/tmp/systemXXXXXX";
  int fd, err;
  hive_h *h;
  hive_node_h root, node, *nodes;
  hive_value_h value;
  char *controlset;
  size_t i;
  char *p;

  /* Locate the SYSTEM hive case-sensitive path. */
  system_path =
    guestfs_case_sensitive_path (g, "/windows/system32/config/system");
  if (!system_path) {
    fprintf (stderr, "virt-dhcp-address: HKLM\\System not found in this guest.");
    exit (EXIT_FAILURE);
  }

  fd = mkstemp (tmpfile);
  if (fd == -1) {
    perror ("mkstemp");
    exit (EXIT_FAILURE);
  }

  /* Download the SYSTEM hive. */
  if (guestfs_download (g, system_path, tmpfile) == -1)
    exit (EXIT_FAILURE);

  free (system_path);

  controlset = guestfs_inspect_get_windows_current_control_set (g, root_fs);
  if (controlset == NULL)
    exit (EXIT_FAILURE);

  /* Open the hive to parse it. */
  h = hivex_open (tmpfile, 0);
  err = errno;
  close (fd);
  unlink (tmpfile);

  if (h == NULL) {
    errno = err;
    perror ("hivex_open");
    exit (EXIT_FAILURE);
  }

  root = hivex_root (h);
  if (root == 0) {
    perror ("hivex_root");
    exit (EXIT_FAILURE);
  }

  /* Get ControlSetXXX\Services\Tcpip\Parameters\Interfaces. */
  const char *path[] = { controlset, "Services", "Tcpip", "Parameters",
                         "Interfaces" };
  node = root;
  errno = 0;
  for (i = 0; node != 0 && i < sizeof path / sizeof path[0]; ++i)
    node = hivex_node_get_child (h, node, path[i]);

  if (node == 0) {
    if (errno != 0)
      perror ("hivex_node_get_child");
    else
      fprintf (stderr, "virt-dhcp-address: HKLM\\System\\%s\\Services\\Tcpip\\Parameters\\Interfaces not found.", controlset);
    exit (EXIT_FAILURE);
  }

  /* Look for a node under here which has a "DhcpIPAddress" entry in it. */
  nodes = hivex_node_children (h, node);
  if (nodes == NULL) {
    perror ("hivex_node_children");
    exit (EXIT_FAILURE);
  }

  value = 0;
  for (i = 0; value == 0 && nodes[i] != 0; ++i) {
    errno = 0;
    value = hivex_node_get_value (h, nodes[i], "DhcpIPAddress");
    if (value == 0 && errno != 0) {
      perror ("hivex_node_get_value");
      exit (EXIT_FAILURE);
    }
  }

  if (value == 0) {
    fprintf (stderr, "virt-dhcp-address: cannot find DHCP address for this guest.\n");
    exit (EXIT_FAILURE);
  }

  /* Get the string and use hivex's auto-conversion to convert it to UTF-8
   * for output.
   */
  p = hivex_value_string (h, value);
  if (!p) {
    perror ("hivex_value_string");
    exit (EXIT_FAILURE);
  }

  printf ("%s\n", p);

  /* Close the hive handle. */
  hivex_close (h);

  free (controlset);
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
