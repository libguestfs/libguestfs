/* virt-p2v
 * Copyright (C) 2015 Red Hat Inc.
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

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <string.h>
#include <ctype.h>
#include <unistd.h>
#include <errno.h>
#include <error.h>
#include <locale.h>
#include <libintl.h>

#include "ignore-value.h"

#include "p2v.h"

#define CHOMP(line,len)                         \
  do {                                          \
    if ((len) > 0 && (line)[(len)-1] == '\n') { \
      (line)[(len)-1] = '\0';                   \
      len--;                                    \
    }                                           \
  } while (0)

/**
 * Return size of a block device, from F</sys/block/I<dev>/size>.
 *
 * This function always succeeds, or else exits (since we expect
 * C<dev> to always be valid and the C<size> file to always exist).
 */
uint64_t
get_blockdev_size (const char *dev)
{
  CLEANUP_FCLOSE FILE *fp = NULL;
  CLEANUP_FREE char *path = NULL;
  CLEANUP_FREE char *size_str = NULL;
  size_t len;
  uint64_t size;

  if (asprintf (&path, "/sys/block/%s/size", dev) == -1)
    error (EXIT_FAILURE, errno, "asprintf");

  fp = fopen (path, "r");
  if (fp == NULL)
    error (EXIT_FAILURE, errno, "fopen: %s", path);
  if (getline (&size_str, &len, fp) == -1)
    error (EXIT_FAILURE, errno, "getline: %s", path);

  if (sscanf (size_str, "%" SCNu64, &size) != 1)
    error (EXIT_FAILURE, 0, "cannot parse %s: %s", path, size_str);

  size /= 2*1024*1024;     /* size from kernel is given in sectors? */
  return size;
}

/**
 * Return model of a block device, from F</sys/block/I<dev>/device/model>.
 *
 * Returns C<NULL> if the file was not found.  The caller must
 * free the returned string.
 */
char *
get_blockdev_model (const char *dev)
{
  CLEANUP_FCLOSE FILE *fp = NULL;
  CLEANUP_FREE char *path = NULL;
  char *model = NULL;
  size_t len = 0;
  ssize_t n;

  if (asprintf (&path, "/sys/block/%s/device/model", dev) == -1)
    error (EXIT_FAILURE, errno, "asprintf");
  fp = fopen (path, "r");
  if (fp == NULL) {
    perror (path);
    return NULL;
  }
  if ((n = getline (&model, &len, fp)) == -1) {
    perror (path);
    free (model);
    return NULL;
  }
  CHOMP (model, n);
  return model;
}

/**
 * Return the serial number of a block device.
 *
 * This is found using the lsblk command.
 *
 * Returns C<NULL> if we could not get the serial number.  The caller
 * must free the returned string.
 */
char *
get_blockdev_serial (const char *dev)
{
  CLEANUP_PCLOSE FILE *fp = NULL;
  CLEANUP_FREE char *cmd = NULL;
  char *serial = NULL;
  size_t len = 0;
  ssize_t n;

  if (asprintf (&cmd, "lsblk -o serial /dev/%s --nodeps --noheadings",
                dev) == -1)
    error (EXIT_FAILURE, errno, "asprintf");
  fp = popen (cmd, "r");
  if (fp == NULL) {
    perror (cmd);
    return NULL;
  }
  if ((n = getline (&serial, &len, fp)) == -1) {
    perror (cmd);
    free (serial);
    return NULL;
  }
  CHOMP (serial, n);
  return serial;
}

/* Return contents of /sys/class/net/<if_name>/address (if found). */
char *
get_if_addr (const char *if_name)
{
  CLEANUP_FCLOSE FILE *fp = NULL;
  CLEANUP_FREE char *path = NULL;
  char *content = NULL;
  size_t len = 0;
  ssize_t n;

  if (asprintf (&path, "/sys/class/net/%s/address", if_name) == -1) {
    perror ("asprintf");
    exit (EXIT_FAILURE);
  }
  fp = fopen (path, "r");
  if (fp == NULL)
    return NULL;
  if ((n = getline (&content, &len, fp)) == -1) {
    perror (path);
    free (content);
    return NULL;
  }
  CHOMP (content, n);
  return content;
}

/* Return contents of /sys/class/net/<if_name>/device/vendor (if found),
 * mapped to the PCI vendor.  See:
 * http://pjwelsh.blogspot.co.uk/2011/11/howto-get-network-card-vendor-device-or.html
 */
char *
get_if_vendor (const char *if_name, int truncate)
{
  CLEANUP_FCLOSE FILE *fp = NULL;
  CLEANUP_FREE char *path = NULL;
  char *line = NULL;
  size_t len = 0;
  ssize_t n;
  char vendor[5];

  if (asprintf (&path, "/sys/class/net/%s/device/vendor", if_name) == -1) {
    perror ("asprintf");
    exit (EXIT_FAILURE);
  }
  fp = fopen (path, "r");
  if (fp == NULL) {
    perror (path);
    return NULL;
  }
  if ((n = getline (&line, &len, fp)) == -1) {
    perror (path);
    free (line);
    return NULL;
  }

  /* Vendor is (always?) a 16 bit quantity (as defined by PCI),
   * something like "0x8086" (for Intel Corp).
   */
  CHOMP (line, n);
  if (line[0] != '0' || line[1] != 'x' || strlen (&line[2]) != 4) {
    free (line);
    return NULL;
  }

  strcpy (vendor, &line[2]);

  fclose (fp);
  fp = fopen ("/usr/share/hwdata/pci.ids", "r");
  if (fp == NULL) {
    perror ("/usr/share/hwdata/pci.ids");
    free (line);
    return NULL;
  }
  while ((n = getline (&line, &len, fp)) != -1) {
    CHOMP (line, n);
    if (STRPREFIX (line, vendor)) {
      /* Find the start of the name after the vendor ID and whitespace. */
      size_t i = 4;
      n -= 4;

      while (n > 0 && isspace (line[i])) {
        i++;
        n--;
      }

      memmove (&line[0], &line[i], n+1 /* copy trailing \0 */);

      /* Truncate? */
      if (truncate > 0 && n > truncate)
        line[n] = '\0';

      return line;
    }
  }

  free (line);
  return NULL;
}

/* Wait for the network to come online, but don't error out if that
 * fails.  The caller will call test_connection immediately after this
 * which will fail if the network didn't come online.
 */

/* XXX We could make this configurable. */
#define NETWORK_ONLINE_COMMAND "nm-online -t 30"

void
wait_network_online (const struct config *config)
{
  if (config->verbose) {
    printf ("waiting for the network to come online ...\n");
    printf ("%s\n", NETWORK_ONLINE_COMMAND);
    fflush (stdout);
  }

  ignore_value (system (NETWORK_ONLINE_COMMAND));
}
