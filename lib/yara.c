/* libguestfs
 * Copyright (C) 2016 Red Hat Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <string.h>
#include <rpc/types.h>
#include <rpc/xdr.h>

#include "guestfs.h"
#include "guestfs_protocol.h"
#include "guestfs-internal.h"
#include "guestfs-internal-all.h"
#include "guestfs-internal-actions.h"

static struct guestfs_yara_detection_list *parse_yara_detection_file (guestfs_h *, const char *);
static int deserialise_yara_detection_list (guestfs_h *, FILE *, struct guestfs_yara_detection_list *);

struct guestfs_yara_detection_list *
guestfs_impl_yara_scan (guestfs_h *g, const char *path)
{
  int r;
  CLEANUP_UNLINK_FREE char *tmpfile = NULL;

  tmpfile = guestfs_int_make_temp_path (g, "yara_scan", NULL);
  if (tmpfile == NULL)
    return NULL;

  r = guestfs_internal_yara_scan (g, path, tmpfile);
  if (r == -1)
    return NULL;

  return parse_yara_detection_file (g, tmpfile);  /* caller frees */
}

/* Parse the file content and return detections list.
 * Return a list of yara_detection on success, NULL on error.
 */
static struct guestfs_yara_detection_list *
parse_yara_detection_file (guestfs_h *g, const char *tmpfile)
{
  int r;
  CLEANUP_FCLOSE FILE *fp = NULL;
  struct guestfs_yara_detection_list *detections = NULL;

  fp = fopen (tmpfile, "r");
  if (fp == NULL) {
    perrorf (g, "fopen: %s", tmpfile);
    return NULL;
  }

  /* Initialise results array. */
  detections = safe_malloc (g, sizeof (*detections));
  detections->len = 8;
  detections->val = safe_malloc (g, detections->len *
                                 sizeof (*detections->val));

  /* Deserialise buffer into detection list. */
  r = deserialise_yara_detection_list (g, fp, detections);
  if (r == -1) {
    guestfs_free_yara_detection_list (detections);
    perrorf (g, "deserialise_yara_detection_list");
    return NULL;
  }

  return detections;
}

/* Deserialise the file content and populate the detection list.
 * Return the number of deserialised detections, -1 on error.
 */
static int
deserialise_yara_detection_list (guestfs_h *g, FILE *fp,
                                 struct guestfs_yara_detection_list *detections)
{
  int r;
  XDR xdr;
  uint32_t index;
  struct stat statbuf;

  r = fstat (fileno(fp), &statbuf);
  if (r == -1) {
    perrorf (g, "fstat");
    return -1;
  }

  xdrstdio_create (&xdr, fp, XDR_DECODE);

  for (index = 0; xdr_getpos (&xdr) < statbuf.st_size; index++) {
    if (index == detections->len) {
      detections->len = 2 * detections->len;
      detections->val = safe_realloc (g, detections->val,
                                      detections->len *
                                      sizeof (*detections->val));
    }

    /* Clear the entry so xdr logic will allocate necessary memory. */
    memset (&detections->val[index], 0, sizeof (*detections->val));
    r = xdr_guestfs_int_yara_detection (&xdr, (guestfs_int_yara_detection *)
                                        &detections->val[index]);
    if (r == 0) {
      perrorf (g, "xdr_guestfs_int_yara_detection");
      break;
    }
  }

  xdr_destroy (&xdr);
  detections->len = index;

  return r ? 0 : -1;
}
