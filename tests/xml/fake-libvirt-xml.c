/* libguestfs
 * Copyright (C) 2012 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>

/* Old <libvirt.h> had a slightly different definition of
 * virDomainGetXMLDesc (using 'int' for flags instead of 'unsigned
 * int').  To avoid an error trying to redefine it with a different
 * declaration, don't include <libvirt.h> at all.  Just copy enough to
 * make the code compile.
 */
typedef struct _virDomain virDomain;
typedef virDomain *virDomainPtr;

char *
virDomainGetXMLDesc (virDomainPtr dom, unsigned int flags)
{
  const char *path;
  int fd;
  struct stat statbuf;
  char *buf, *p;
  size_t n;
  ssize_t r;

  path = getenv ("FAKE_LIBVIRT_XML");

  if (!path) {
    fprintf (stderr, "environment variable FAKE_LIBVIRT_XML is not set\n");
    _exit (1);
  }

  fprintf (stderr,
           "fake_libvirt_xml: returning fake libvirt XML from %s\n", path);

  fd = open (path, O_RDONLY | O_CLOEXEC);
  if (fd == -1) {
    perror (path);
    _exit (1);
  }

  if (fstat (fd, &statbuf) == -1) {
    perror ("fstat");
    _exit (1);
  }

  buf = malloc (statbuf.st_size + 1);
  if (buf == NULL) {
    perror ("malloc");
    _exit (1);
  }

  for (n = 0, p = buf; n < statbuf.st_size; ++n) {
    r = read (fd, p, statbuf.st_size - n);
    if (r == -1) {
      perror ("read");
      _exit (1);
    }
    if (r == 0)
      break;
    n += r;
    p += r;
  }

  *p = '\0';

  if (close (fd) == -1) {
    perror ("close");
    _exit (1);
  }

  return buf;                   /* caller frees */
}
