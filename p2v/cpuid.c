/* virt-p2v
 * Copyright (C) 2009-2017 Red Hat Inc.
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

/**
 * Process CPU capabilities into libvirt-compatible C<E<lt>cpuE<gt>> data.
 *
 * If libvirt is available at compile time then this is quite
 * simple - libvirt API C<virConnectGetCapabilities> provides
 * a C<E<lt>hostE<ge>> element which has mostly what we need.
 *
 * Flags C<acpi>, C<apic>, C<pae> still have to be parsed out of
 * F</proc/cpuinfo> because these will not necessarily be present in
 * the libvirt capabilities directly (they are implied by the
 * processor model, requiring a complex lookup in the CPU map).
 *
 * Note that #vCPUs and amount of RAM is handled by F<main.c>.
 *
 * See: L<https://libvirt.org/formatdomain.html#elementsCPU>
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <errno.h>
#include <libintl.h>

#ifdef HAVE_LIBVIRT
#include <libvirt/libvirt.h>
#include <libvirt/virterror.h>
#endif

#include <libxml/xpath.h>

#include "getprogname.h"
#include "ignore-value.h"

#include "p2v.h"

static void
free_cpu_config (struct cpu_config *cpu)
{
  if (cpu->vendor)
    free (cpu->vendor);
  if (cpu->model)
    free (cpu->model);
  memset (cpu, 0, sizeof *cpu);
}

/**
 * Read flags from F</proc/cpuinfo>.
 */
static void
cpuinfo_flags (struct cpu_config *cpu)
{
  const char *cmd;
  CLEANUP_PCLOSE FILE *fp = NULL;
  CLEANUP_FREE char *flag = NULL;
  ssize_t len;
  size_t buflen = 0;

  /* Get the flags, one per line. */
  cmd = "< /proc/cpuinfo "
#if defined(__arm__)
    "grep ^Features"
#else
    "grep ^flags"
#endif
    " | awk '{ for (i = 3; i <= NF; ++i) { print $i }; exit }'";

  fp = popen (cmd, "re");
  if (fp == NULL) {
    perror ("/proc/cpuinfo");
    return;
  }

  while (errno = 0, (len = getline (&flag, &buflen, fp)) != -1) {
    if (len > 0 && flag[len-1] == '\n')
      flag[len-1] = '\0';

    if (STREQ (flag, "acpi"))
      cpu->acpi = 1;
    else if (STREQ (flag, "apic"))
      cpu->apic = 1;
    else if (STREQ (flag, "pae"))
      cpu->pae = 1;
  }

  if (errno) {
    perror ("getline");
    return;
  }
}

#ifdef HAVE_LIBVIRT

static void
ignore_errors (void *ignore, virErrorPtr ignore2)
{
  /* empty */
}

static void libvirt_error (const char *fs, ...) __attribute__((format (printf,1,2)));

static void
libvirt_error (const char *fs, ...)
{
  va_list args;
  CLEANUP_FREE char *msg = NULL;
  int len;
  virErrorPtr err;

  va_start (args, fs);
  len = vasprintf (&msg, fs, args);
  va_end (args);

  if (len < 0) goto fallback;

  /* In all recent libvirt, this retrieves the thread-local error. */
  err = virGetLastError ();
  if (err)
    fprintf (stderr,
             "%s: %s: %s [code=%d int1=%d]\n",
             getprogname (), msg, err->message, err->code, err->int1);
  else
  fallback:
    fprintf (stderr, "%s: %s\n", getprogname (), msg);
}

/**
 * Read the capabilities from libvirt and parse out the fields
 * we care about.
 */
static void
libvirt_capabilities (struct cpu_config *cpu)
{
  virConnectPtr conn;
  CLEANUP_FREE char *capabilities_xml = NULL;
  CLEANUP_XMLFREEDOC xmlDocPtr doc = NULL;
  CLEANUP_XMLXPATHFREECONTEXT xmlXPathContextPtr xpathCtx = NULL;
  CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xpathObj = NULL;
  const char *xpathexpr;
  xmlNodeSetPtr nodes;
  size_t nr_nodes, i;
  xmlNodePtr node;

  /* Connect to libvirt and get the capabilities XML. */
  conn = virConnectOpenReadOnly (NULL);
  if (!conn) {
    libvirt_error (_("could not connect to libvirt"));
    return;
  }

  /* Suppress default behaviour of printing errors to stderr.  Note
   * you can't set this to NULL to ignore errors; setting it to NULL
   * restores the default error handler ...
   */
  virConnSetErrorFunc (conn, NULL, ignore_errors);

  capabilities_xml = virConnectGetCapabilities (conn);
  if (!capabilities_xml) {
    libvirt_error (_("could not get libvirt capabilities"));
    virConnectClose (conn);
    return;
  }

  /* Parse the capabilities XML with libxml2. */
  doc = xmlReadMemory (capabilities_xml, strlen (capabilities_xml),
                       NULL, NULL, XML_PARSE_NONET);
  if (doc == NULL) {
    fprintf (stderr,
             _("%s: unable to parse capabilities XML returned by libvirt\n"),
             getprogname ());
    virConnectClose (conn);
    return;
  }

  xpathCtx = xmlXPathNewContext (doc);
  if (xpathCtx == NULL) {
    fprintf (stderr, _("%s: unable to create new XPath context\n"),
             getprogname ());
    virConnectClose (conn);
    return;
  }

  /* Get the CPU vendor. */
  xpathexpr = "/capabilities/host/cpu/vendor/text()";
  xpathObj = xmlXPathEvalExpression (BAD_CAST xpathexpr, xpathCtx);
  if (xpathObj == NULL) {
    fprintf (stderr, _("%s: unable to evaluate xpath expression: %s\n"),
             getprogname (), xpathexpr);
    virConnectClose (conn);
    return;
  }
  nodes = xpathObj->nodesetval;
  nr_nodes = nodes->nodeNr;
  if (nr_nodes > 0) {
    node = nodes->nodeTab[0];
    cpu->vendor = (char *) xmlNodeGetContent (node);
  }

  /* Get the CPU model. */
  xmlXPathFreeObject (xpathObj);
  xpathexpr = "/capabilities/host/cpu/model/text()";
  xpathObj = xmlXPathEvalExpression (BAD_CAST xpathexpr, xpathCtx);
  if (xpathObj == NULL) {
    fprintf (stderr, _("%s: unable to evaluate xpath expression: %s\n"),
             getprogname (), xpathexpr);
    virConnectClose (conn);
    return;
  }
  nodes = xpathObj->nodesetval;
  nr_nodes = nodes->nodeNr;
  if (nr_nodes > 0) {
    node = nodes->nodeTab[0];
    cpu->model = (char *) xmlNodeGetContent (node);
  }

  /* Get the topology.  Note the XPath expression returns all
   * attributes of the <topology> node.
   */
  xmlXPathFreeObject (xpathObj);
  xpathexpr = "/capabilities/host/cpu/topology/@*";
  xpathObj = xmlXPathEvalExpression (BAD_CAST xpathexpr, xpathCtx);
  if (xpathObj == NULL) {
    fprintf (stderr, _("%s: unable to evaluate xpath expression: %s\n"),
             getprogname (), xpathexpr);
    virConnectClose (conn);
    return;
  }
  nodes = xpathObj->nodesetval;
  nr_nodes = nodes->nodeNr;
  /* Iterate over the attributes of the <topology> node. */
  for (i = 0; i < nr_nodes; ++i) {
    node = nodes->nodeTab[i];

    if (node->type == XML_ATTRIBUTE_NODE) {
      xmlAttrPtr attr = (xmlAttrPtr) node;
      CLEANUP_FREE char *content = NULL;
      unsigned *up;

      if (STREQ ((const char *) attr->name, "sockets")) {
        up = &cpu->sockets;
      parse_attr:
        *up = 0;
        content = (char *) xmlNodeListGetString (doc, attr->children, 1);
        if (content)
          ignore_value (sscanf (content, "%u", up));
      }
      else if (STREQ ((const char *) attr->name, "cores")) {
        up = &cpu->cores;
        goto parse_attr;
      }
      else if (STREQ ((const char *) attr->name, "threads")) {
        up = &cpu->threads;
        goto parse_attr;
      }
    }
  }

  virConnectClose (conn);
}

#else /* !HAVE_LIBVIRT */

static void
libvirt_capabilities (struct cpu_config *cpu)
{
  fprintf (stderr,
           _("%s: program was compiled without libvirt support\n"),
           getprogname ());
}

#endif /* !HAVE_LIBVIRT */

void
get_cpu_config (struct cpu_config *cpu)
{
  free_cpu_config (cpu);
  libvirt_capabilities (cpu);
  cpuinfo_flags (cpu);
}
