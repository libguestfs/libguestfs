/* Example showing how to enable debugging, and capture it into any
 * custom logging system (syslog in this example, but any could be
 * used).  Note this uses the event API which is also available in
 * non-C language bindings.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <syslog.h>
#include <guestfs.h>

static void message_callback (guestfs_h *g, void *opaque, uint64_t event, int event_handle, int flags, const char *buf, size_t buf_len, const uint64_t *array, size_t array_len);

/* Events we are interested in.  This bitmask covers all trace and
 * debug messages.
 */
static const uint64_t event_bitmask =
  GUESTFS_EVENT_LIBRARY |
  GUESTFS_EVENT_WARNING |
  GUESTFS_EVENT_APPLIANCE |
  GUESTFS_EVENT_TRACE;

int
main (int argc, char *argv[])
{
  guestfs_h *g;

  g = guestfs_create ();
  if (g == NULL) {
    perror ("failed to create libguestfs handle");
    exit (EXIT_FAILURE);
  }

  /* By default, debugging information is printed on stderr.  To
   * capture it somewhere else you have to set up an event handler
   * which will be called back as debug messages are generated.  To do
   * this use the event API.
   *
   * For more information see EVENTS in guestfs(3).
   */
  if (guestfs_set_event_callback (g, message_callback,
                                  event_bitmask, 0, NULL) == -1)
    exit (EXIT_FAILURE);

  /* This is how debugging is enabled:
   *
   * Setting the 'trace' flag in the handle means that each libguestfs
   * call is logged (name, parameters, return).  This flag is useful
   * to see how libguestfs is being used by a program.
   *
   * Setting the 'verbose' flag enables a great deal of extra
   * debugging throughout the system.  This is useful if there is a
   * libguestfs error which you don't understand.
   *
   * Note that you should set the flags early on after creating the
   * handle.  In particular if you set the verbose flag after launch
   * then you won't see all messages.
   *
   * For more information see:
   * http://libguestfs.org/guestfs-faq.1.html#debugging-libguestfs
   *
   * Error messages raised by APIs are *not* debugging information,
   * and they are not affected by any of this.  You may have to log
   * them separately.
   */
  guestfs_set_trace (g, 1);
  guestfs_set_verbose (g, 1);

  /* Do some operations which will generate plenty of trace and debug
   * messages.
   */
  if (guestfs_add_drive (g, "/dev/null") == -1)
    exit (EXIT_FAILURE);

  printf ("There is no output from this program.  "
          "Take a look in your system log file,\n"
          "eg. /var/log/messages.\n");

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  guestfs_close (g);

  exit (EXIT_SUCCESS);
}

/* This function is called back by libguestfs whenever a trace or
 * debug message is generated.
 *
 * For the classes of events we have registered above, 'array' and
 * 'array_len' will not be meaningful.  Only 'buf' and 'buf_len' will
 * be interesting and these will contain the trace or debug message.
 *
 * This example simply redirects these messages to syslog, but
 * obviously you could do something more advanced here.
 */
static void
message_callback (guestfs_h *g, void *opaque,
                  uint64_t event, int event_handle,
                  int flags,
                  const char *buf, size_t buf_len,
                  const uint64_t *array, size_t array_len)
{
  const int priority = LOG_USER|LOG_INFO;
  char *event_name, *msg;

  if (buf_len > 0) {
    event_name = guestfs_event_to_string (event);
    msg = strndup (buf, buf_len);
    syslog (priority, "[%s] %s", event_name, msg);
    free (msg);
    free (event_name);
  }
}
