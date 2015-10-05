/* Example of using the libvirt authentication event-driven API.
 *
 * See "LIBVIRT AUTHENTICATION" in guestfs(3).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <guestfs.h>

static void
usage (void)
{
  fprintf (stderr,
	   "Usage:\n"
	   "\n"
	   "  libvirt-auth URI domain\n"
	   "\n"
	   "where:\n"
	   "\n"
	   "  URI     is the libvirt URI, eg. qemu+libssh2://USER@localhost/system\n"
	   "  domain  is the name of the guest\n"
	   "\n"
	   "Example:\n"
	   "\n"
	   "  libvirt-auth 'qemu+libssh2://USER@localhost/system' 'foo'\n"
	   "\n"
	   "would connect (read-only) to libvirt URI given and open the guest\n"
	   "called 'foo' and list some information about its filesystems.\n"
	   "\n"
	   "The important point of this example is that any libvirt authentication\n"
	   "required to connect to the server should be done.\n"
	   "\n");
}

static void auth_callback (guestfs_h *g, void *opaque, uint64_t event, int event_handle, int flags, const char *buf, size_t buf_len, const uint64_t *array, size_t array_len);

int
main (int argc, char *argv[])
{
  const char *uri, *dom;
  guestfs_h *g;
  const char *creds[] = { "authname", "passphrase",
                          "echoprompt", "noechoprompt", NULL };
  int r, eh;
  char **filesystems;
  size_t i;

  if (argc != 3) {
    usage ();
    exit (EXIT_FAILURE);
  }
  uri = argv[1];
  dom = argv[2];

  g = guestfs_create ();
  if (!g)
    exit (EXIT_FAILURE);

  r = guestfs_set_libvirt_supported_credentials (g, (char **) creds);
  if (r == -1)
    exit (EXIT_FAILURE);

  /* Set up the event handler. */
  eh = guestfs_set_event_callback (g, auth_callback,
                                   GUESTFS_EVENT_LIBVIRT_AUTH, 0, NULL);
  if (eh == -1)
    exit (EXIT_FAILURE);

  /* Add the named domain. */
  r = guestfs_add_domain (g, dom,
                          GUESTFS_ADD_DOMAIN_LIBVIRTURI, uri,
                          -1);
  if (r == -1)
    exit (EXIT_FAILURE);

  /* Launch and do some simple inspection. */
  r = guestfs_launch (g);
  if (r == -1)
    exit (EXIT_FAILURE);

  filesystems = guestfs_list_filesystems (g);
  if (filesystems == NULL)
    exit (EXIT_FAILURE);

  for (i = 0; filesystems[i] != NULL; i += 2) {
    printf ("%s:%s is a %s filesystem\n",
            dom, filesystems[i], filesystems[i+1]);
    free (filesystems[i]);
    free (filesystems[i+1]);
  }
  free (filesystems);

  exit (EXIT_SUCCESS);
}

static void
auth_callback (guestfs_h *g,
               void *opaque,
               uint64_t event,
               int event_handle,
               int flags,
               const char *buf, size_t buf_len,
               const uint64_t *array, size_t array_len)
{
  char **creds;
  size_t i;
  char *prompt;
  char *reply = NULL;
  size_t allocsize = 0;
  char *pass;
  ssize_t len;
  int r;

  printf ("libvirt-auth.c: authentication required for libvirt URI '%s'\n\n",
          buf);

  /* Ask libguestfs what credentials libvirt is demanding. */
  creds = guestfs_get_libvirt_requested_credentials (g);
  if (creds == NULL)
    exit (EXIT_FAILURE);

  /* Now ask the user for answers. */
  for (i = 0; creds[i] != NULL; ++i)
  {
    printf ("libvirt-auth.c: credential '%s'\n", creds[i]);

    if (strcmp (creds[i], "authname") == 0 ||
        strcmp (creds[i], "echoprompt") == 0) {
      prompt = guestfs_get_libvirt_requested_credential_prompt (g, i);
      if (prompt && strcmp (prompt, "") != 0)
        printf ("%s: ", prompt);
      free (prompt);

      len = getline (&reply, &allocsize, stdin);
      if (len == -1) {
        perror ("getline");
        exit (EXIT_FAILURE);
      }
      if (len > 0 && reply[len-1] == '\n')
        reply[--len] = '\0';

      r = guestfs_set_libvirt_requested_credential (g, i, reply, len);
      if (r == -1)
        exit (EXIT_FAILURE);
    } else if (strcmp (creds[i], "passphrase") == 0 ||
               strcmp (creds[i], "noechoprompt") == 0) {
      prompt = guestfs_get_libvirt_requested_credential_prompt (g, i);
      if (prompt && strcmp (prompt, "") != 0)
        printf ("%s: ", prompt);
      free (prompt);

      pass = getpass ("");
      if (pass == NULL) {
        perror ("getpass");
        exit (EXIT_FAILURE);
      }
      len = strlen (pass);

      r = guestfs_set_libvirt_requested_credential (g, i, pass, len);
      if (r == -1)
        exit (EXIT_FAILURE);
    }

    free (creds[i]);
  }

  free (reply);
  free (creds);
}
