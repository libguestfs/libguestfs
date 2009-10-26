/* hivexml - Convert Windows Registry "hive" to XML file.
 * Copyright (C) 2009 Red Hat Inc.
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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <inttypes.h>
#include <unistd.h>
#include <errno.h>

#include <libxml/xmlwriter.h>

#include "hivex.h"

/* Callback functions. */
static int node_start (hive_h *, void *, hive_node_h, const char *name);
static int node_end (hive_h *, void *, hive_node_h, const char *name);
static int value_string (hive_h *, void *, hive_node_h, hive_value_h, hive_type t, size_t len, const char *key, const char *str);
static int value_multiple_strings (hive_h *, void *, hive_node_h, hive_value_h, hive_type t, size_t len, const char *key, char **argv);
static int value_string_invalid_utf16 (hive_h *, void *, hive_node_h, hive_value_h, hive_type t, size_t len, const char *key, const char *str);
static int value_dword (hive_h *, void *, hive_node_h, hive_value_h, hive_type t, size_t len, const char *key, int32_t);
static int value_qword (hive_h *, void *, hive_node_h, hive_value_h, hive_type t, size_t len, const char *key, int64_t);
static int value_binary (hive_h *, void *, hive_node_h, hive_value_h, hive_type t, size_t len, const char *key, const char *value);
static int value_none (hive_h *, void *, hive_node_h, hive_value_h, hive_type t, size_t len, const char *key, const char *value);
static int value_other (hive_h *, void *, hive_node_h, hive_value_h, hive_type t, size_t len, const char *key, const char *value);

static struct hivex_visitor visitor = {
  .node_start = node_start,
  .node_end = node_end,
  .value_string = value_string,
  .value_multiple_strings = value_multiple_strings,
  .value_string_invalid_utf16 = value_string_invalid_utf16,
  .value_dword = value_dword,
  .value_qword = value_qword,
  .value_binary = value_binary,
  .value_none = value_none,
  .value_other = value_other
};

#define XML_CHECK(proc, args)                                           \
  do {                                                                  \
    if ((proc args) == -1) {                                            \
      fprintf (stderr, "%s: failed to write XML document\n", #proc);    \
      exit (1);                                                         \
    }                                                                   \
  } while (0)

int
main (int argc, char *argv[])
{
  int c;
  int open_flags = 0;
  int visit_flags = 0;

  while ((c = getopt (argc, argv, "dk")) != EOF) {
    switch (c) {
    case 'd':
      open_flags |= HIVEX_OPEN_DEBUG;
      break;
    case 'k':
      visit_flags |= HIVEX_VISIT_SKIP_BAD;
      break;
    default:
      fprintf (stderr, "hivexml [-dk] regfile > output.xml\n");
      exit (1);
    }
  }

  if (optind + 1 != argc) {
    fprintf (stderr, "hivexml: missing name of input file\n");
    exit (1);
  }

  hive_h *h = hivex_open (argv[optind], open_flags);
  if (h == NULL) {
    perror (argv[optind]);
    exit (1);
  }

  /* Note both this macro, and xmlTextWriterStartDocument leak memory.  There
   * doesn't seem to be any way to recover that memory, but it's not a
   * large amount.
   */
  LIBXML_TEST_VERSION;

  xmlTextWriterPtr writer;
  writer = xmlNewTextWriterFilename ("/dev/stdout", 0);
  if (writer == NULL) {
    fprintf (stderr, "xmlNewTextWriterFilename: failed to create XML writer\n");
    exit (1);
  }

  XML_CHECK (xmlTextWriterStartDocument, (writer, NULL, "utf-8", NULL));
  XML_CHECK (xmlTextWriterStartElement, (writer, BAD_CAST "hive"));

  if (hivex_visit (h, &visitor, sizeof visitor, writer, visit_flags) == -1) {
    perror (argv[optind]);
    exit (1);
  }

  if (hivex_close (h) == -1) {
    perror (argv[optind]);
    exit (1);
  }

  XML_CHECK (xmlTextWriterEndElement, (writer));
  XML_CHECK (xmlTextWriterEndDocument, (writer));
  xmlFreeTextWriter (writer);

  exit (0);
}

static int
node_start (hive_h *h, void *writer_v, hive_node_h node, const char *name)
{
  xmlTextWriterPtr writer = (xmlTextWriterPtr) writer_v;
  XML_CHECK (xmlTextWriterStartElement, (writer, BAD_CAST "node"));
  XML_CHECK (xmlTextWriterWriteAttribute, (writer, BAD_CAST "name", BAD_CAST name));
  return 0;
}

static int
node_end (hive_h *h, void *writer_v, hive_node_h node, const char *name)
{
  xmlTextWriterPtr writer = (xmlTextWriterPtr) writer_v;
  XML_CHECK (xmlTextWriterEndElement, (writer));
  return 0;
}

static void
start_value (xmlTextWriterPtr writer,
             const char *key, const char *type, const char *encoding)
{
  XML_CHECK (xmlTextWriterStartElement, (writer, BAD_CAST "value"));
  XML_CHECK (xmlTextWriterWriteAttribute, (writer, BAD_CAST "type", BAD_CAST type));
  if (encoding)
    XML_CHECK (xmlTextWriterWriteAttribute, (writer, BAD_CAST "encoding", BAD_CAST encoding));
  if (*key)
    XML_CHECK (xmlTextWriterWriteAttribute, (writer, BAD_CAST "key", BAD_CAST key));
  else                          /* default key */
    XML_CHECK (xmlTextWriterWriteAttribute, (writer, BAD_CAST "default", BAD_CAST "1"));
}

static void
end_value (xmlTextWriterPtr writer)
{
  XML_CHECK (xmlTextWriterEndElement, (writer));
}

static int
value_string (hive_h *h, void *writer_v, hive_node_h node, hive_value_h value,
              hive_type t, size_t len, const char *key, const char *str)
{
  xmlTextWriterPtr writer = (xmlTextWriterPtr) writer_v;
  const char *type;

  switch (t) {
  case hive_t_string: type = "string"; break;
  case hive_t_expand_string: type = "expand"; break;
  case hive_t_link: type = "link"; break;

  case hive_t_none:
  case hive_t_binary:
  case hive_t_dword:
  case hive_t_dword_be:
  case hive_t_multiple_strings:
  case hive_t_resource_list:
  case hive_t_full_resource_description:
  case hive_t_resource_requirements_list:
  case hive_t_qword:
    abort ();                   /* internal error - should not happen */

  default:
    type = "unknown";
  }

  start_value (writer, key, type, NULL);
  XML_CHECK (xmlTextWriterWriteString, (writer, BAD_CAST str));
  end_value (writer);
  return 0;
}

static int
value_multiple_strings (hive_h *h, void *writer_v, hive_node_h node,
                        hive_value_h value, hive_type t, size_t len,
                        const char *key, char **argv)
{
  xmlTextWriterPtr writer = (xmlTextWriterPtr) writer_v;
  start_value (writer, key, "string-list", NULL);

  size_t i;
  for (i = 0; argv[i] != NULL; ++i) {
    XML_CHECK (xmlTextWriterStartElement, (writer, BAD_CAST "string"));
    XML_CHECK (xmlTextWriterWriteString, (writer, BAD_CAST argv[i]));
    XML_CHECK (xmlTextWriterEndElement, (writer));
  }

  end_value (writer);
  return 0;
}

static int
value_string_invalid_utf16 (hive_h *h, void *writer_v, hive_node_h node,
                            hive_value_h value, hive_type t, size_t len,
                            const char *key,
                            const char *str /* original data */)
{
  xmlTextWriterPtr writer = (xmlTextWriterPtr) writer_v;
  const char *type;

  switch (t) {
  case hive_t_string: type = "bad-string"; break;
  case hive_t_expand_string: type = "bad-expand"; break;
  case hive_t_link: type = "bad-link"; break;
  case hive_t_multiple_strings: type = "bad-string-list"; break;

  case hive_t_none:
  case hive_t_binary:
  case hive_t_dword:
  case hive_t_dword_be:
  case hive_t_resource_list:
  case hive_t_full_resource_description:
  case hive_t_resource_requirements_list:
  case hive_t_qword:
    abort ();                   /* internal error - should not happen */

  default:
    type = "unknown";
  }

  start_value (writer, key, type, "base64");
  XML_CHECK (xmlTextWriterWriteBase64, (writer, str, 0, len));
  end_value (writer);

  return 0;
}

static int
value_dword (hive_h *h, void *writer_v, hive_node_h node, hive_value_h value,
             hive_type t, size_t len, const char *key, int32_t v)
{
  xmlTextWriterPtr writer = (xmlTextWriterPtr) writer_v;
  start_value (writer, key, "int32", NULL);
  XML_CHECK (xmlTextWriterWriteFormatString, (writer, "%" PRIi32, v));
  end_value (writer);
  return 0;
}

static int
value_qword (hive_h *h, void *writer_v, hive_node_h node, hive_value_h value,
             hive_type t, size_t len, const char *key, int64_t v)
{
  xmlTextWriterPtr writer = (xmlTextWriterPtr) writer_v;
  start_value (writer, key, "int64", NULL);
  XML_CHECK (xmlTextWriterWriteFormatString, (writer, "%" PRIi64, v));
  end_value (writer);
  return 0;
}

static int
value_binary (hive_h *h, void *writer_v, hive_node_h node, hive_value_h value,
              hive_type t, size_t len, const char *key, const char *v)
{
  xmlTextWriterPtr writer = (xmlTextWriterPtr) writer_v;
  start_value (writer, key, "binary", "base64");
  XML_CHECK (xmlTextWriterWriteBase64, (writer, v, 0, len));
  end_value (writer);
  return 0;
}

static int
value_none (hive_h *h, void *writer_v, hive_node_h node, hive_value_h value,
            hive_type t, size_t len, const char *key, const char *v)
{
  xmlTextWriterPtr writer = (xmlTextWriterPtr) writer_v;
  start_value (writer, key, "none", "base64");
  if (len > 0) XML_CHECK (xmlTextWriterWriteBase64, (writer, v, 0, len));
  end_value (writer);
  return 0;
}

static int
value_other (hive_h *h, void *writer_v, hive_node_h node, hive_value_h value,
             hive_type t, size_t len, const char *key, const char *v)
{
  xmlTextWriterPtr writer = (xmlTextWriterPtr) writer_v;
  const char *type;

  switch (t) {
  case hive_t_none:
  case hive_t_binary:
  case hive_t_dword:
  case hive_t_dword_be:
  case hive_t_qword:
  case hive_t_string:
  case hive_t_expand_string:
  case hive_t_link:
  case hive_t_multiple_strings:
    abort ();                   /* internal error - should not happen */

  case hive_t_resource_list: type = "resource-list"; break;
  case hive_t_full_resource_description: type = "resource-description"; break;
  case hive_t_resource_requirements_list: type = "resource-requirements"; break;

  default:
    type = "unknown";
  }

  start_value (writer, key, type, "base64");
  if (len > 0) XML_CHECK (xmlTextWriterWriteBase64, (writer, v, 0, len));
  end_value (writer);

  return 0;
}
