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
#include <string.h>
#include <ctype.h>
#include <unistd.h>
#include <locale.h>
#include <libintl.h>

#include "p2v.h"

#define CHOMP(line,len)                         \
  do {                                          \
    if ((len) > 0 && (line)[(len)-1] == '\n') { \
      (line)[(len)-1] = '\0';                   \
      len--;                                    \
    }                                           \
  } while (0)

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
