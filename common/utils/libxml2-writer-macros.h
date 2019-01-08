/* libguestfs
 * Copyright (C) 2009-2019 Red Hat Inc.
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

/**
 * These macros make it easier to write XML.  To use them correctly
 * you must be aware of these assumptions:
 *
 * =over 4
 *
 * =item *
 *
 * The C<xmlTextWriterPtr> is called C<xo>.  It is used implicitly
 * by all the macros.
 *
 * =item *
 *
 * On failure, a function called C<xml_error> is called which you must
 * define (usually as a macro).  You must use C<CLEANUP_*> macros in
 * your functions if you want correct cleanup of local variables along
 * the error path.
 *
 * =item *
 *
 * All the "bad" casting is hidden inside the macros.
 *
 * =back
 */

#ifndef GUESTFS_LIBXML2_WRITER_MACROS_H_
#define GUESTFS_LIBXML2_WRITER_MACROS_H_

#include <stdarg.h>

/**
 * To define an XML element use:
 *
 *  start_element ("name") {
 *    ...
 *  } end_element ();
 *
 * which produces C<<< <name>...</name> >>>
 */
#define start_element(element)						\
  if (xmlTextWriterStartElement (xo, BAD_CAST (element)) == -1) {	\
    xml_error ("xmlTextWriterStartElement");				\
  }									\
  do

#define end_element()				\
  while (0);					\
  do {						\
    if (xmlTextWriterEndElement (xo) == -1) {	\
      xml_error ("xmlTextWriterEndElement");	\
    }						\
  } while (0)

/**
 * To define an empty element:
 *
 *  empty_element ("name");
 *
 * which produces C<<< <name/> >>>
 */
#define empty_element(element)                                  \
  do { start_element ((element)) {} end_element (); } while (0)

/**
 * To define a single element with no attributes containing some text:
 *
 *  single_element ("name", text);
 *
 * which produces C<<< <name>text</name> >>>
 */
#define single_element(element,str)             \
  do {                                          \
    start_element ((element)) {                 \
      string ((str));                           \
    } end_element ();                           \
  } while (0)

/**
 * To define a single element with no attributes containing some text
 * using a format string:
 *
 *  single_element_format ("cores", "%d", nr_cores);
 *
 * which produces C<<< <cores>4</cores> >>>
 */
#define single_element_format(element,fs,...)   \
  do {                                          \
    start_element ((element)) {                 \
      string_format ((fs), ##__VA_ARGS__);      \
    } end_element ();                           \
  } while (0)

/**
 * To define an XML element with attributes, use:
 *
 *  start_element ("name") {
 *    attribute ("foo", "bar");
 *    attribute_format ("count", "%d", count);
 *    ...
 *  } end_element ();
 *
 * which produces C<<< <name foo="bar" count="123">...</name> >>>
 */
#define attribute(key,value)                                            \
  do {                                                                  \
    if (xmlTextWriterWriteAttribute (xo, BAD_CAST (key),                \
                                     BAD_CAST (value)) == -1) {         \
      xml_error ("xmlTextWriterWriteAttribute");                        \
    }                                                                   \
  } while (0)

#define attribute_format(key,fs,...)                                    \
  do {                                                                  \
    if (xmlTextWriterWriteFormatAttribute (xo, BAD_CAST (key),          \
                                           fs, ##__VA_ARGS__) == -1) {  \
      xml_error ("xmlTextWriterWriteFormatAttribute");                  \
    }                                                                   \
  } while (0)

/**
 * C<attribute_ns (prefix, key, namespace_uri, value)> defines a
 * namespaced attribute.
 */
#define attribute_ns(prefix,key,namespace_uri,value)                    \
  do {                                                                  \
    if (xmlTextWriterWriteAttributeNS (xo, BAD_CAST (prefix),           \
                                       BAD_CAST (key),                  \
                                       BAD_CAST (namespace_uri),        \
                                       BAD_CAST (value)) == -1) {       \
      xml_error ("xmlTextWriterWriteAttribute");                        \
    }                                                                   \
  } while (0)

/**
 * To define a verbatim string, use:
 *
 *  string ("hello");
 */
#define string(str)                                                     \
  do {                                                                  \
    if (xmlTextWriterWriteString (xo, BAD_CAST(str)) == -1) {           \
      xml_error ("xmlTextWriterWriteString");                           \
    }                                                                   \
  } while (0)

/**
 * To define a verbatim string using a format string, use:
 *
 *  string ("%s, world", greeting);
 */
#define string_format(fs,...)                                           \
  do {                                                                  \
    if (xmlTextWriterWriteFormatString (xo, fs, ##__VA_ARGS__) == -1) { \
      xml_error ("xmlTextWriterWriteFormatString");                     \
    }                                                                   \
  } while (0)

/**
 * To write a string encoded as base64:
 *
 *  base64 (data, size);
 */
#define base64(data, size)                                              \
  do {                                                                  \
    if (xmlTextWriterWriteBase64 (xo, (data), 0, (size)) == -1) {       \
      xml_error ("xmlTextWriterWriteBase64");                           \
    }                                                                   \
  } while (0)

/**
 * To define a comment in the XML, use:
 *
 *   comment ("number of items = %d", nr_items);
 */
#define comment(fs,...)                                                 \
  do {                                                                  \
    if (xmlTextWriterWriteFormatComment (xo, fs, ##__VA_ARGS__) == -1) { \
      xml_error ("xmlTextWriterWriteFormatComment");                    \
    }                                                                   \
  } while (0)

#endif /* GUESTFS_LIBXML2_WRITER_MACROS_H_ */
