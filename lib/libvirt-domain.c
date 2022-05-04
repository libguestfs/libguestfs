/* libguestfs
 * Copyright (C) 2010 Red Hat Inc.
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
#include <stdbool.h>
#include <assert.h>
#include <string.h>
#include <libintl.h>

#ifdef HAVE_LIBVIRT
#include <libvirt/virterror.h>
#endif

#include <libxml/xpath.h>
#include <libxml/parser.h>
#include <libxml/tree.h>

#include "base64.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"

#if defined(HAVE_LIBVIRT)

static xmlDocPtr get_domain_xml (guestfs_h *g, virDomainPtr dom);
static ssize_t for_each_disk (guestfs_h *g, virConnectPtr conn, xmlDocPtr doc, int (*f) (guestfs_h *g, const char *filename, const char *format, int readonly, const char *protocol, char *const *server, const char *username, const char *secret, int blocksize, void *data), void *data);
static int libvirt_selinux_label (guestfs_h *g, xmlDocPtr doc, char **label_rtn, char **imagelabel_rtn);
static char *filename_from_pool (guestfs_h *g, virConnectPtr conn, const char *pool_nane, const char *volume_name);
static bool xpath_object_is_empty (xmlXPathObjectPtr obj);
static char *xpath_object_get_string (xmlDocPtr doc, xmlXPathObjectPtr obj);
static int xpath_object_get_int (xmlDocPtr doc, xmlXPathObjectPtr obj);

static void
ignore_errors (void *ignore, virErrorPtr ignore2)
{
  /* empty */
}

int
guestfs_impl_add_domain (guestfs_h *g, const char *domain_name,
			 const struct guestfs_add_domain_argv *optargs)
{
  virErrorPtr err;
  virConnectPtr conn = NULL;
  virDomainPtr dom = NULL;
  int r = -1;
  const char *libvirturi;
  int readonly;
  int live;
  int allowuuid;
  const char *readonlydisk;
  const char *cachemode;
  const char *discard;
  bool copyonread;
  struct guestfs_add_libvirt_dom_argv optargs2 = { .bitmask = 0 };

  libvirturi = optargs->bitmask & GUESTFS_ADD_DOMAIN_LIBVIRTURI_BITMASK
    ? optargs->libvirturi : NULL;
  readonly = optargs->bitmask & GUESTFS_ADD_DOMAIN_READONLY_BITMASK
    ? optargs->readonly : 0;
  live = optargs->bitmask & GUESTFS_ADD_DOMAIN_LIVE_BITMASK
    ? optargs->live : 0;
  allowuuid = optargs->bitmask & GUESTFS_ADD_DOMAIN_ALLOWUUID_BITMASK
    ? optargs->allowuuid : 0;
  readonlydisk = optargs->bitmask & GUESTFS_ADD_DOMAIN_READONLYDISK_BITMASK
    ? optargs->readonlydisk : NULL;
  cachemode = optargs->bitmask & GUESTFS_ADD_DOMAIN_CACHEMODE_BITMASK
    ? optargs->cachemode : NULL;
  discard = optargs->bitmask & GUESTFS_ADD_DOMAIN_DISCARD_BITMASK
    ? optargs->discard : NULL;
  copyonread = optargs->bitmask & GUESTFS_ADD_DOMAIN_COPYONREAD_BITMASK
    ? optargs->copyonread : false;

  if (live) {
    error (g, _("libguestfs live support was removed in libguestfs 1.48"));
    return -1;
  }

  /* Connect to libvirt, find the domain.  We cannot open the connection
   * in read-only mode (VIR_CONNECT_RO), as that kind of connection
   * is considered untrusted, and thus libvirt will prevent to read
   * the values of secrets.
   */
  conn = guestfs_int_open_libvirt_connection (g, libvirturi, 0);
  if (!conn) {
    err = virGetLastError ();
    error (g, _("could not connect to libvirt (code %d, domain %d): %s"),
           err->code, err->domain, err->message);
    goto cleanup;
  }

  /* Suppress default behaviour of printing errors to stderr.  Note
   * you can't set this to NULL to ignore errors; setting it to NULL
   * restores the default error handler ...
   */
  virConnSetErrorFunc (conn, NULL, ignore_errors);

  /* Try UUID first. */
  if (allowuuid)
    dom = virDomainLookupByUUIDString (conn, domain_name);

  /* Try ordinary domain name. */
  if (!dom)
    dom = virDomainLookupByName (conn, domain_name);

  if (!dom) {
    err = virGetLastError ();
    error (g, _("no libvirt domain called ‘%s’: %s"),
           domain_name, err->message);
    goto cleanup;
  }

  if (readonly) {
    optargs2.bitmask |= GUESTFS_ADD_LIBVIRT_DOM_READONLY_BITMASK;
    optargs2.readonly = readonly;
  }
  if (live) {
    error (g, _("libguestfs live support was removed in libguestfs 1.48"));
    goto cleanup;
  }
  if (readonlydisk) {
    optargs2.bitmask |= GUESTFS_ADD_LIBVIRT_DOM_READONLYDISK_BITMASK;
    optargs2.readonlydisk = readonlydisk;
  }
  if (cachemode) {
    optargs2.bitmask |= GUESTFS_ADD_LIBVIRT_DOM_CACHEMODE_BITMASK;
    optargs2.cachemode = cachemode;
  }
  if (discard) {
    optargs2.bitmask |= GUESTFS_ADD_LIBVIRT_DOM_DISCARD_BITMASK;
    optargs2.discard = discard;
  }
  if (copyonread) {
    optargs2.bitmask |= GUESTFS_ADD_LIBVIRT_DOM_COPYONREAD_BITMASK;
    optargs2.copyonread = copyonread;
  }

  r = guestfs_add_libvirt_dom_argv (g, dom, &optargs2);

 cleanup:
  if (dom) virDomainFree (dom);
  if (conn) virConnectClose (conn);

  return r;
}

static int add_disk (guestfs_h *g, const char *filename, const char *format, int readonly, const char *protocol, char *const *server, const char *username, const char *secret, int blocksize, void *data);

enum readonlydisk {
  readonlydisk_error,
  readonlydisk_read,
  readonlydisk_write,
  readonlydisk_ignore,
};

struct add_disk_data {
  int readonly;
  enum readonlydisk readonlydisk;
  /* Other args to pass through to add_drive_opts. */
  struct guestfs_add_drive_opts_argv optargs;
};

int
guestfs_impl_add_libvirt_dom (guestfs_h *g, void *domvp,
			      const struct guestfs_add_libvirt_dom_argv *optargs)
{
  virDomainPtr dom = domvp;
  ssize_t r;
  int readonly;
  const char *cachemode;
  const char *discard;
  bool copyonread;
  int live;
  /* Default for back-compat reasons: */
  enum readonlydisk readonlydisk = readonlydisk_write;
  size_t ckp;
  struct add_disk_data data;
  CLEANUP_XMLFREEDOC xmlDocPtr doc = NULL;
  CLEANUP_FREE char *label = NULL, *imagelabel = NULL;

  readonly =
    optargs->bitmask & GUESTFS_ADD_LIBVIRT_DOM_READONLY_BITMASK
    ? optargs->readonly : 0;
  live =
    optargs->bitmask & GUESTFS_ADD_LIBVIRT_DOM_LIVE_BITMASK
    ? optargs->live : 0;

  if ((optargs->bitmask & GUESTFS_ADD_LIBVIRT_DOM_READONLYDISK_BITMASK)) {
    if (STREQ (optargs->readonlydisk, "error"))
      readonlydisk = readonlydisk_error;
    else if (STREQ (optargs->readonlydisk, "read"))
      readonlydisk = readonlydisk_read;
    else if (STREQ (optargs->readonlydisk, "write"))
      readonlydisk = readonlydisk_write;
    else if (STREQ (optargs->readonlydisk, "ignore"))
      readonlydisk = readonlydisk_ignore;
    else {
      error (g, _("unknown readonlydisk parameter"));
      return -1;
    }
  }

  cachemode =
    optargs->bitmask & GUESTFS_ADD_LIBVIRT_DOM_CACHEMODE_BITMASK
    ? optargs->cachemode : NULL;

  discard =
    optargs->bitmask & GUESTFS_ADD_LIBVIRT_DOM_DISCARD_BITMASK
    ? optargs->discard : NULL;

  copyonread =
    optargs->bitmask & GUESTFS_ADD_LIBVIRT_DOM_COPYONREAD_BITMASK
    ? optargs->copyonread : false;

  if (live) {
    error (g, _("libguestfs live support was removed in libguestfs 1.48"));
    return -1;
  }

  if (!readonly) {
    virDomainInfo info;
    virErrorPtr err;
    int vm_running;

    if (virDomainGetInfo (dom, &info) == -1) {
      err = virGetLastError ();
      error (g, _("error getting domain info: %s"), err->message);
      return -1;
    }
    vm_running = info.state != VIR_DOMAIN_SHUTOFF;
    if (vm_running) {
      /* Dangerous to modify the disks of a running VM. */
      error (g, _("error: domain is a live virtual machine.\n"
                  "Writing to the disks of a running virtual machine can cause disk corruption.\n"
                  "Use read-only access.  In most libguestfs tools use --ro."));
      return -1;
    }
  }

  /* Domain XML. */
  if ((doc = get_domain_xml (g, dom)) == NULL)
    return -1;

  /* Find and pass the SELinux security label to the libvirt back end.
   * Note this has to happen before adding the disks, since those may
   * use the label.
   */
  if (libvirt_selinux_label (g, doc, &label, &imagelabel) == -1)
    return -1;
  if (label && imagelabel) {
    guestfs_set_backend_setting (g, "internal_libvirt_label", label);
    guestfs_set_backend_setting (g, "internal_libvirt_imagelabel", imagelabel);
    guestfs_set_backend_setting (g, "internal_libvirt_norelabel_disks", "1");
  }
  else
    guestfs_clear_backend_setting (g, "internal_libvirt_norelabel_disks");

  /* Add the disks. */
  data.optargs.bitmask = 0;
  data.readonly = readonly;
  data.readonlydisk = readonlydisk;
  if (cachemode) {
    data.optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_CACHEMODE_BITMASK;
    data.optargs.cachemode = cachemode;
  }
  if (discard) {
    data.optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_DISCARD_BITMASK;
    data.optargs.discard = discard;
  }
  if (copyonread) {
    data.optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_COPYONREAD_BITMASK;
    data.optargs.copyonread = copyonread;
  }

  /* Checkpoint the command line around the operation so that either
   * all disks are added or none are added.
   */
  ckp = guestfs_int_checkpoint_drives (g);
  r = for_each_disk (g, virDomainGetConnect (dom), doc, add_disk, &data);
  if (r == -1)
    guestfs_int_rollback_drives (g, ckp);

  return r;
}

static int
add_disk (guestfs_h *g,
          const char *filename, const char *format, int readonly_in_xml,
          const char *protocol, char *const *server, const char *username,
          const char *secret, int blocksize, void *datavp)
{
  struct add_disk_data *data = datavp;
  /* Copy whole struct so we can make local changes: */
  struct guestfs_add_drive_opts_argv optargs = data->optargs;
  int readonly = -1, error = 0, skip = 0;

  if (readonly_in_xml) {        /* <readonly/> appears in the XML */
    if (data->readonly) {       /* asked to add disk read-only */
      switch (data->readonlydisk) {
      case readonlydisk_error: readonly = 1; break;
      case readonlydisk_read: readonly = 1; break;
      case readonlydisk_write: readonly = 1; break;
      case readonlydisk_ignore: skip = 1; break;
      }
    } else {                    /* asked to add disk for read/write */
      switch (data->readonlydisk) {
      case readonlydisk_error: error = 1; break;
      case readonlydisk_read: readonly = 1; break;
      case readonlydisk_write: readonly = 0; break;
      case readonlydisk_ignore: skip = 1; break;
      }
    }
  } else                        /* no <readonly/> in XML */
    readonly = data->readonly;

  if (skip)
    return 0;

  if (error) {
    error (g, _("%s: disk is marked <readonly/> in libvirt XML, and readonlydisk was set to \"error\""),
           filename);
    return -1;
  }

  if (readonly == -1)
    abort ();

  optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_READONLY_BITMASK;
  optargs.readonly = readonly;

  if (format) {
    optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_FORMAT_BITMASK;
    optargs.format = format;
  }
  if (protocol) {
    optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_PROTOCOL_BITMASK;
    optargs.protocol = protocol;
  }
  if (server) {
    optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_SERVER_BITMASK;
    optargs.server = server;
  }
  if (username) {
    optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_USERNAME_BITMASK;
    optargs.username = username;
  }
  if (secret) {
    optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_SECRET_BITMASK;
    optargs.secret = secret;
  }
  if (blocksize) {
    optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_BLOCKSIZE_BITMASK;
    optargs.blocksize = blocksize;
  }

  return guestfs_add_drive_opts_argv (g, filename, &optargs);
}

/* Find the <seclabel/> element in the libvirt XML, and if it exists
 * get the SELinux process label and image label from it.
 *
 * The reason for all this is because of sVirt:
 * https://bugzilla.redhat.com/show_bug.cgi?id=912499#c7
 */
static int
libvirt_selinux_label (guestfs_h *g, xmlDocPtr doc,
                       char **label_rtn, char **imagelabel_rtn)
{
  CLEANUP_XMLXPATHFREECONTEXT xmlXPathContextPtr xpathCtx = NULL;
  CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xpathObj = NULL;
  xmlNodeSetPtr nodes;
  size_t nr_nodes;
  xmlNodePtr node, child;
  bool gotlabel = 0, gotimagelabel = 0;

  xpathCtx = xmlXPathNewContext (doc);
  if (xpathCtx == NULL) {
    error (g, _("unable to create new XPath context"));
    return -1;
  }

  /* Typical seclabel element looks like this:
   *
   * <domain>
   *   <seclabel type='dynamic' model='selinux' relabel='yes'>
   *     <label>system_u:system_r:svirt_t:s0:c24,c151</label>
   *     <imagelabel>system_u:object_r:svirt_image_t:s0:c24,c151</imagelabel>
   *   </seclabel>
   *
   * This code restricts our search to model=selinux labels (since in
   * theory at least multiple seclabel elements might be present).
   */
  const char *xpath_expr = "/domain/seclabel[@model='selinux']";
  xpathObj = xmlXPathEvalExpression (BAD_CAST xpath_expr, xpathCtx);
  if (xpathObj == NULL) {
    error (g, _("unable to evaluate XPath expression"));
    return -1;
  }

  nodes = xpathObj->nodesetval;
  if (nodes == NULL)
    return 0;

  nr_nodes = nodes->nodeNr;

  if (nr_nodes == 0)
    return 0;
  if (nr_nodes > 1) {
    debug (g, "ignoring %zu nodes matching '%s'", nr_nodes, xpath_expr);
    return 0;
  }

  node = nodes->nodeTab[0];
  if (node->type != XML_ELEMENT_NODE) {
    error (g, _("expected <seclabel/> to be an XML element"));
    return -1;
  }

  /* Find the <label/> and <imagelabel/> child nodes. */
  for (child = node->children; child != NULL; child = child->next) {
    if (!gotlabel && STREQ ((char *) child->name, "label")) {
      /* Get the label content. */
      *label_rtn = (char *) xmlNodeGetContent (child);
      gotlabel = 1;
    }
    if (!gotimagelabel && STREQ ((char *) child->name, "imagelabel")) {
      /* Get the imagelabel content. */
      *imagelabel_rtn = (char *) xmlNodeGetContent (child);
      gotimagelabel = 1;
    }
  }

  return 0;
}

/* The callback function 'f' is called once for each disk.
 *
 * Returns number of disks, or -1 if there was an error.
 */
static ssize_t
for_each_disk (guestfs_h *g,
               virConnectPtr conn,
               xmlDocPtr doc,
               int (*f) (guestfs_h *g,
                         const char *filename, const char *format,
                         int readonly,
                         const char *protocol, char *const *server,
                         const char *username, const char *secret,
                         int blocksize, void *data),
               void *data)
{
  size_t i, nr_added = 0, nr_nodes;
  CLEANUP_XMLXPATHFREECONTEXT xmlXPathContextPtr xpathCtx = NULL;
  CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xpathObj = NULL;
  xmlNodeSetPtr nodes;

  /* Now the horrible task of parsing out the fields we need from the XML.
   * http://www.xmlsoft.org/examples/xpath1.c
   */
  xpathCtx = xmlXPathNewContext (doc);
  if (xpathCtx == NULL) {
    error (g, _("unable to create new XPath context"));
    return -1;
  }

  /* This gives us a set of all the <disk> nodes. */
  xpathObj = xmlXPathEvalExpression (BAD_CAST "//devices/disk", xpathCtx);
  if (xpathObj == NULL) {
    error (g, _("unable to evaluate XPath expression"));
    return -1;
  }

  nodes = xpathObj->nodesetval;
  if (nodes != NULL) {
    nr_nodes = nodes->nodeNr;
    for (i = 0; i < nr_nodes; ++i) {
      CLEANUP_FREE char *type = NULL, *filename = NULL, *format = NULL, *protocol = NULL, *username = NULL, *secret = NULL;
      CLEANUP_FREE_STRING_LIST char **server = NULL;
      CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xptype = NULL;
      CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xpformat = NULL;
      CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xpreadonly = NULL;
      CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xplbs = NULL;
      CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xpfilename = NULL;
      CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xpprotocol = NULL;
      CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xphost = NULL;
      CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xpusername = NULL;
      CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xppool = NULL;
      CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xpvolume = NULL;
      int readonly;
      int blocksize = 0;
      int t;
      virErrorPtr err;

      /* Change the context to the current <disk> node.
       * DV advises to reset this before each search since older versions of
       * libxml2 might overwrite it.
       */
      xpathCtx->node = nodes->nodeTab[i];

      /* Filename can be in <source dev=..> or <source file=..> attribute.
       * Check the <disk type=..> attribute first to find out which one.
       */
      xptype = xmlXPathEvalExpression (BAD_CAST "./@type", xpathCtx);
      if (xpath_object_is_empty (xptype))
        continue;               /* no type attribute, skip it */
      type = xpath_object_get_string (doc, xptype);

      if (STREQ (type, "file")) { /* type = "file" so look at source/@file */
        xpathCtx->node = nodes->nodeTab[i];
        xpfilename = xmlXPathEvalExpression (BAD_CAST "./source/@file",
                                             xpathCtx);
        if (xpath_object_is_empty (xpfilename))
          continue;           /* disk filename not found, skip this */
      } else if (STREQ (type, "block")) { /* type = "block", use source/@dev */
        xpathCtx->node = nodes->nodeTab[i];
        xpfilename = xmlXPathEvalExpression (BAD_CAST "./source/@dev",
                                             xpathCtx);
        if (xpath_object_is_empty (xpfilename))
          continue;           /* disk filename not found, skip this */
      } else if (STREQ (type, "network")) { /* type = "network", use source/@name */
        int hi;

        debug (g, "disk[%zu]: network device", i);
        xpathCtx->node = nodes->nodeTab[i];

        /* Get the protocol (e.g. "rbd").  Required. */
        xpprotocol = xmlXPathEvalExpression (BAD_CAST "./source/@protocol",
                                             xpathCtx);
        if (xpath_object_is_empty (xpprotocol))
          continue;
        protocol = xpath_object_get_string (doc, xpprotocol);
        debug (g, "disk[%zu]: protocol: %s", i, protocol);

        /* <source name="..."> is the path/exportname.  Optional. */
        xpfilename = xmlXPathEvalExpression (BAD_CAST "./source/@name",
                                             xpathCtx);
        if (xpfilename == NULL ||
            xpfilename->nodesetval == NULL)
          continue;

        /* <auth username="...">.  Optional. */
        xpusername = xmlXPathEvalExpression (BAD_CAST "./auth/@username",
                                             xpathCtx);
        if (!xpath_object_is_empty (xpusername)) {
          CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xpsecrettype = NULL;
          CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xpsecretuuid = NULL;
          CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xpsecretusage = NULL;
          CLEANUP_FREE char *typestr = NULL;
          unsigned char *value = NULL;
          size_t value_size = 0;

          username = xpath_object_get_string (doc, xpusername);
          debug (g, "disk[%zu]: username: %s", i, username);

          /* <secret type="...">.  Mandatory given <auth> is specified. */
          xpsecrettype = xmlXPathEvalExpression (BAD_CAST "./auth/secret/@type",
                                                 xpathCtx);
          if (xpath_object_is_empty (xpsecrettype))
            continue;
          typestr = xpath_object_get_string (doc, xpsecrettype);

          /* <secret uuid="..."> and <secret usage="...">.
           * At least one of them is required.
           */
          xpsecretuuid = xmlXPathEvalExpression (BAD_CAST "./auth/secret/@uuid",
                                                 xpathCtx);
          xpsecretusage = xmlXPathEvalExpression (BAD_CAST "./auth/secret/@usage",
                                                  xpathCtx);
          if (!xpath_object_is_empty (xpsecretuuid)) {
            CLEANUP_FREE char *uuidstr = NULL;
            virSecretPtr sec;

            uuidstr = xpath_object_get_string (doc, xpsecretuuid);
            debug (g, "disk[%zu]: secret type: %s; UUID: %s",
                   i, typestr, uuidstr);
            sec = virSecretLookupByUUIDString (conn, uuidstr);
            if (sec == NULL) {
              err = virGetLastError ();
              error (g, _("no secret with UUID ‘%s’: %s"),
                     uuidstr, err ? err->message : "(none)");
              continue;
            }

            value = virSecretGetValue (sec, &value_size, 0);
            if (value == NULL) {
              err = virGetLastError ();
              error (g, _("cannot get the value of the secret with UUID ‘%s’: %s"),
                     uuidstr, err->message);
              virSecretFree (sec);
              continue;
            }

            virSecretFree (sec);
          } else if (!xpath_object_is_empty (xpsecretusage)) {
            virSecretUsageType usageType;
            CLEANUP_FREE char *usagestr = NULL;
            virSecretPtr sec;

            usagestr = xpath_object_get_string (doc, xpsecretusage);
            debug (g, "disk[%zu]: secret type: %s; usage: %s",
                   i, typestr, usagestr);
            if (STREQ (typestr, "none"))
              usageType = VIR_SECRET_USAGE_TYPE_NONE;
            else if (STREQ (typestr, "volume"))
              usageType = VIR_SECRET_USAGE_TYPE_VOLUME;
            else if (STREQ (typestr, "ceph"))
              usageType = VIR_SECRET_USAGE_TYPE_CEPH;
            else if (STREQ (typestr, "iscsi"))
              usageType = VIR_SECRET_USAGE_TYPE_ISCSI;
            else
              continue;
            sec = virSecretLookupByUsage (conn, usageType, usagestr);
            if (sec == NULL) {
              err = virGetLastError ();
              error (g, _("no secret for usage ‘%s’: %s"),
                     usagestr, err->message);
              continue;
            }

            value = virSecretGetValue (sec, &value_size, 0);
            if (value == NULL) {
              err = virGetLastError ();
              error (g, _("cannot get the value of the secret with usage ‘%s’: %s"),
                     usagestr, err->message);
              virSecretFree (sec);
              continue;
            }

            virSecretFree (sec);
          } else {
            continue;
          }

          assert (value != NULL);
          assert (value_size > 0);

          if (STREQ (typestr, "ceph")) {
            const size_t res = base64_encode_alloc ((const char *) value,
                                                    value_size, &secret);
            free (value);
            if (res == 0 || secret == NULL) {
              error (g, "internal error: cannot encode the rbd secret as base64");
              return -1;
            }
          } else {
            secret = (char *) value;
          }

          assert (secret != NULL);
        }

        xphost = xmlXPathEvalExpression (BAD_CAST "./source/host",
					 xpathCtx);
        if (xphost == NULL ||
            xphost->nodesetval == NULL)
          continue;

        /* This gives us a list of <host> elements, which each have a
         * 'name' and 'port' attribute which we want to put into a
         * string, joined by a ':'.
         */
        server = safe_malloc (g, sizeof (char *) *
                              (xphost->nodesetval->nodeNr + 1));
        for (hi = 0; hi < xphost->nodesetval->nodeNr ; hi++) {
          xmlChar *name, *port;
          xmlNodePtr h = xphost->nodesetval->nodeTab[hi];
          int r;

          assert (h);
          assert (h->type == XML_ELEMENT_NODE);
          name = xmlGetProp (h, BAD_CAST "name");
          assert (name);        // libvirt checks this
          port = xmlGetProp (h, BAD_CAST "port");
          debug (g, "disk[%zu]: hostname: %s port: %s",
                 i, name, port ? (char *) port : "(not set)");
          if (port)
            r = asprintf (&server[hi], "%s:%s", name, port);
          else
            r = asprintf (&server[hi], "%s", name);
          if (r == -1) {
            perrorf (g, "asprintf");
            return -1;
          }
        }
        server[xphost->nodesetval->nodeNr] = NULL;
      } else if (STREQ (type, "volume")) { /* type = "volume", use source/@volume */
        CLEANUP_FREE char *pool = NULL;
        CLEANUP_FREE char *volume = NULL;

        xpathCtx->node = nodes->nodeTab[i];

        /* Get the source pool.  Required. */
        xppool = xmlXPathEvalExpression (BAD_CAST "./source/@pool",
                                         xpathCtx);
        if (xpath_object_is_empty (xppool))
          continue;
        pool = xpath_object_get_string (doc, xppool);

        /* Get the source volume.  Required. */
        xpvolume = xmlXPathEvalExpression (BAD_CAST "./source/@volume",
                                           xpathCtx);
        if (xpath_object_is_empty (xpvolume))
          continue;
        volume = xpath_object_get_string (doc, xpvolume);

        debug (g, "disk[%zu]: pool: %s; volume: %s", i, pool, volume);

        filename = filename_from_pool (g, conn, pool, volume);
        if (filename == NULL)
          continue; /* filename_from_pool already called error() */
      } else
        continue; /* type is not handled above, skip it */

      /* Allow any of the code blocks above (handling a disk type)
       * to directly get the filename (setting 'filename'), with no need
       * for an XPath evaluation.
       */
      if (filename == NULL) {
        assert (xpfilename);
        assert (xpfilename->nodesetval);
        if (xpfilename->nodesetval->nodeNr > 0)
          filename = xpath_object_get_string (doc, xpfilename);
        else
          /* For network protocols (eg. nbd), name may be omitted. */
          filename = safe_strdup (g, "");
      }

      debug (g, "disk[%zu]: filename: %s", i, filename);

      /* Get the disk format (may not be set). */
      xpathCtx->node = nodes->nodeTab[i];
      xpformat = xmlXPathEvalExpression (BAD_CAST "./driver/@type", xpathCtx);
      if (!xpath_object_is_empty (xpformat))
        format = xpath_object_get_string (doc, xpformat);

      /* Get the <readonly/> flag. */
      xpathCtx->node = nodes->nodeTab[i];
      xpreadonly = xmlXPathEvalExpression (BAD_CAST "./readonly", xpathCtx);
      readonly = 0;
      if (!xpath_object_is_empty (xpreadonly))
        readonly = 1;

      /* Get logical block size.  Optional. */
      xpathCtx->node = nodes->nodeTab[i];
      xplbs = xmlXPathEvalExpression (BAD_CAST
                                      "./blockio/@logical_block_size",
                                      xpathCtx);
      if (!xpath_object_is_empty (xplbs))
        blocksize = xpath_object_get_int (doc, xplbs);

      if (f)
        t = f (g, filename, format, readonly, protocol, server, username,
               secret, blocksize, data);
      else
        t = 0;

      if (t == -1)
        return -1;

      nr_added++;
    }
  }

  if (nr_added == 0) {
    error (g, _("libvirt domain has no disks"));
    return -1;
  }

  /* Successful. */
  return nr_added;
}

static xmlDocPtr
get_domain_xml (guestfs_h *g, virDomainPtr dom)
{
  virErrorPtr err;
  xmlDocPtr doc;

  CLEANUP_FREE char *xml = virDomainGetXMLDesc (dom, 0);
  if (!xml) {
    err = virGetLastError ();
    error (g, _("error reading libvirt XML information: %s"), err->message);
    return NULL;
  }

  debug (g, "original domain XML:\n%s", xml);

  /* Parse the domain XML into an XML document. */
  doc = xmlReadMemory (xml, strlen (xml),
                       NULL, NULL, XML_PARSE_NONET);
  if (doc == NULL) {
    error (g, _("unable to parse XML information returned by libvirt"));
    return NULL;
  }

  return doc;
}

static char *
filename_from_pool (guestfs_h *g, virConnectPtr conn,
                    const char *pool_name, const char *volume_name)
{
  char *filename = NULL;
  virErrorPtr err;
  virStoragePoolPtr pool = NULL;
  virStorageVolPtr vol = NULL;
  virStorageVolInfo info;
  int ret;

  pool = virStoragePoolLookupByName (conn, pool_name);
  if (pool == NULL) {
    err = virGetLastError ();
    error (g, _("no libvirt pool called ‘%s’: %s"),
           pool_name, err->message);
    goto cleanup;
  }

  vol = virStorageVolLookupByName (pool, volume_name);
  if (vol == NULL) {
    err = virGetLastError ();
    error (g, _("no volume called ‘%s’ in the libvirt pool ‘%s’: %s"),
           volume_name, pool_name, err->message);
    goto cleanup;
  }

  ret = virStorageVolGetInfo (vol, &info);
  if (ret < 0) {
    err = virGetLastError ();
    error (g, _("cannot get information of the libvirt volume ‘%s’: %s"),
           volume_name, err->message);
    goto cleanup;
  }

  debug (g, "type of libvirt volume %s: %d", volume_name, info.type);

  /* Support only file-based volumes for now. */
  if (info.type != VIR_STORAGE_VOL_FILE)
    goto cleanup;

  filename = virStorageVolGetPath (vol);
  if (filename == NULL) {
    err = virGetLastError ();
    error (g, _("cannot get the filename of the libvirt volume ‘%s’: %s"),
           volume_name, err->message);
    goto cleanup;
  }

 cleanup:
  if (vol) virStorageVolFree (vol);
  if (pool) virStoragePoolFree (pool);

  return filename;
}

/* Check that C<obj> is not empty.
 */
static bool
xpath_object_is_empty (xmlXPathObjectPtr obj)
{
  return obj == NULL ||
         obj->nodesetval == NULL ||
         obj->nodesetval->nodeNr == 0;
}

/* Get the string value from C<obj>.
 *
 * C<obj> is I<required> to not be empty, i.e. that C<xpath_object_is_empty>
 * is C<false>.
 */
static char *
xpath_object_get_string (xmlDocPtr doc, xmlXPathObjectPtr obj)
{
  xmlAttrPtr attr;
  char *value;

  assert (obj->nodesetval->nodeTab[0]);
  assert (obj->nodesetval->nodeTab[0]->type == XML_ATTRIBUTE_NODE);
  attr = (xmlAttrPtr) obj->nodesetval->nodeTab[0];
  value = (char *) xmlNodeListGetString (doc, attr->children, 1);

  return value;
}

/* Get the integer value from C<obj>.
 *
 * C<obj> is I<required> to not be empty, i.e. that C<xpath_object_is_empty>
 * is C<false>.
 *
 * Any parsing errors are ignored and 0 (zero) will be returned.
 */
static int
xpath_object_get_int (xmlDocPtr doc, xmlXPathObjectPtr obj)
{
  xmlAttrPtr attr;
  CLEANUP_FREE char *str;
  int value;

  assert (obj->nodesetval->nodeTab[0]);
  assert (obj->nodesetval->nodeTab[0]->type == XML_ATTRIBUTE_NODE);
  attr = (xmlAttrPtr) obj->nodesetval->nodeTab[0];
  str = (char *) xmlNodeListGetString (doc, attr->children, 1);

  if (sscanf (str, "%d", &value) != 1)
    value = 0; /* ignore any parsing error */

  return value;
}

#else /* no libvirt at compile time */

#define NOT_IMPL(r)                                                     \
  error (g, _("add-domain API not available since this version of libguestfs was compiled without libvirt")); \
  return r

int
guestfs_impl_add_domain (guestfs_h *g, const char *dom,
			 const struct guestfs_add_domain_argv *optargs)
{
  NOT_IMPL(-1);
}

int
guestfs_impl_add_libvirt_dom (guestfs_h *g, void *domvp,
			      const struct guestfs_add_libvirt_dom_argv *optargs)
{
  NOT_IMPL(-1);
}

#endif /* no libvirt at compile time */
