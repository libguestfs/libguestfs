/* Bindings for libxml2
 * Copyright (C) 2009-2017 Red Hat Inc.
 * Copyright (C) 2017 SUSE Inc.
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

/**
 * Mini interface to libxml2.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>
#include <libxml/uri.h>

#pragma GCC diagnostic ignored "-Wmissing-prototypes"

/* xmlDocPtr type */
#define docptr_val(v) (*((xmlDocPtr *)Data_custom_val(v)))

static struct custom_operations docptr_custom_operations = {
  (char *) "docptr_custom_operations",
  custom_finalize_default,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default
};

value
mllib_xml_free_docptr (value docv)
{
  CAMLparam1 (docv);
  xmlDocPtr doc = docptr_val (docv);

  xmlFreeDoc (doc);
  CAMLreturn (Val_unit);
}

/* xmlXPathContextPtr type */
#define xpathctxptr_val(v) (*((xmlXPathContextPtr *)Data_custom_val(v)))

static struct custom_operations xpathctxptr_custom_operations = {
  (char *) "xpathctxptr_custom_operations",
  custom_finalize_default,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default
};

value
mllib_xml_free_xpathctxptr (value xpathctxv)
{
  CAMLparam1 (xpathctxv);
  xmlXPathContextPtr xpathctx = xpathctxptr_val (xpathctxv);

  xmlXPathFreeContext (xpathctx);
  CAMLreturn (Val_unit);
}

/* xmlXPathObjectPtr type */
#define xpathobjptr_val(v) (*((xmlXPathObjectPtr *)Data_custom_val(v)))

static struct custom_operations xpathobjptr_custom_operations = {
  (char *) "xpathobjptr_custom_operations",
  custom_finalize_default,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default
};

value
mllib_xml_free_xpathobjptr (value xpathobjv)
{
  CAMLparam1 (xpathobjv);
  xmlXPathObjectPtr xpathobj = xpathobjptr_val (xpathobjv);

  xmlXPathFreeObject (xpathobj);
  CAMLreturn (Val_unit);
}

value
mllib_xml_parse_memory (value xmlv)
{
  CAMLparam1 (xmlv);
  CAMLlocal1 (docv);
  xmlDocPtr doc;

  /* For security reasons, call xmlReadMemory (not xmlParseMemory) and
   * pass XML_PARSE_NONET.  See commit 845daded5fddc70f.
   */
  doc = xmlReadMemory (String_val (xmlv), caml_string_length (xmlv),
                       NULL, NULL, XML_PARSE_NONET);
  if (doc == NULL)
    caml_invalid_argument ("parse_memory: unable to parse XML");

  docv = caml_alloc_custom (&docptr_custom_operations, sizeof (xmlDocPtr),
                            0, 1);
  docptr_val (docv) = doc;

  CAMLreturn (docv);
}

value
mllib_xml_parse_file (value filenamev)
{
  CAMLparam1 (filenamev);
  CAMLlocal1 (docv);
  xmlDocPtr doc;

  /* For security reasons, call xmlReadFile (not xmlParseFile) and
   * pass XML_PARSE_NONET.  See commit 845daded5fddc70f.
   */
  doc = xmlReadFile (String_val (filenamev), NULL, XML_PARSE_NONET);
  if (doc == NULL)
    caml_invalid_argument ("parse_file: unable to parse XML from file");

  docv = caml_alloc_custom (&docptr_custom_operations, sizeof (xmlDocPtr),
                            0, 1);
  docptr_val (docv) = doc;

  CAMLreturn (docv);
}

value
mllib_xml_copy_doc (value docv, value recursivev)
{
  CAMLparam2 (docv, recursivev);
  CAMLlocal1 (copyv);
  xmlDocPtr doc, copy;

  doc = docptr_val (docv);
  copy = xmlCopyDoc (doc, Bool_val (recursivev));
  if (copy == NULL)
    caml_invalid_argument ("copy_doc: failed to copy");

  copyv = caml_alloc_custom (&docptr_custom_operations, sizeof (xmlDocPtr),
                             0, 1);
  docptr_val (copyv) = copy;

  CAMLreturn (copyv);
}

value
mllib_xml_to_string (value docv, value formatv)
{
  CAMLparam2 (docv, formatv);
  CAMLlocal1 (strv);
  xmlDocPtr doc;
  xmlChar *mem;
  int size;

  doc = docptr_val (docv);
  xmlDocDumpFormatMemory (doc, &mem, &size, Bool_val (formatv));

  strv = caml_alloc_string (size);
  memcpy (String_val (strv), mem, size);
  free (mem);

  CAMLreturn (strv);
}

value
mllib_xml_xpath_new_context (value docv)
{
  CAMLparam1 (docv);
  CAMLlocal1 (xpathctxv);
  xmlDocPtr doc;
  xmlXPathContextPtr xpathctx;

  doc = docptr_val (docv);
  xpathctx = xmlXPathNewContext (doc);
  if (xpathctx == NULL)
    caml_invalid_argument ("xpath_new_context: unable to create xmlXPathNewContext");

  xpathctxv = caml_alloc_custom (&xpathctxptr_custom_operations,
                                 sizeof (xmlXPathContextPtr), 0, 1);
  xpathctxptr_val (xpathctxv) = xpathctx;

  CAMLreturn (xpathctxv);
}

value
mllib_xml_xpathctxptr_register_ns (value xpathctxv, value prefix, value uri)
{
  CAMLparam3 (xpathctxv, prefix, uri);
  xmlXPathContextPtr xpathctx;
  int r;

  xpathctx = xpathctxptr_val (xpathctxv);
  r = xmlXPathRegisterNs (xpathctx,
                          BAD_CAST String_val (prefix),
                          BAD_CAST String_val (uri));
  if (r == -1)
    caml_invalid_argument ("xpath_register_ns: unable to register namespace");

  CAMLreturn (Val_unit);
}

value
mllib_xml_xpathctxptr_eval_expression (value xpathctxv, value exprv)
{
  CAMLparam2 (xpathctxv, exprv);
  CAMLlocal1 (xpathobjv);
  xmlXPathContextPtr xpathctx;
  xmlXPathObjectPtr xpathobj;

  xpathctx = xpathctxptr_val (xpathctxv);
  xpathobj = xmlXPathEvalExpression (BAD_CAST String_val (exprv), xpathctx);
  if (xpathobj == NULL)
    caml_invalid_argument ("xpath_eval_expression: unable to evaluate XPath expression");

  xpathobjv = caml_alloc_custom (&xpathobjptr_custom_operations,
                                 sizeof (xmlXPathObjectPtr), 0, 1);
  xpathobjptr_val (xpathobjv) = xpathobj;

  CAMLreturn (xpathobjv);
}

value
mllib_xml_xpathobjptr_nr_nodes (value xpathobjv)
{
  CAMLparam1 (xpathobjv);
  xmlXPathObjectPtr xpathobj = xpathobjptr_val (xpathobjv);

  if (xpathobj->nodesetval == NULL)
    CAMLreturn (Val_int (0));
  else
    CAMLreturn (Val_int (xpathobj->nodesetval->nodeNr));
}

value
mllib_xml_xpathobjptr_get_nodeptr (value xpathobjv, value iv)
{
  CAMLparam2 (xpathobjv, iv);
  xmlXPathObjectPtr xpathobj = xpathobjptr_val (xpathobjv);
  const int i = Int_val (iv);

  if (i < 0 || i >= xpathobj->nodesetval->nodeNr)
    caml_invalid_argument ("get_nodeptr: node number out of range");

  /* Because xmlNodePtrs are owned by the document, we don't want to
   * wrap this up with a finalizer, so just pass the pointer straight
   * back to OCaml as a value.  OCaml will ignore it because it's
   * outside the heap, and just pass it back to us when needed.  This
   * relies on the xmlDocPtr not being freed, but we pair the node
   * pointer with the doc in the OCaml layer so the GC will not free
   * one without freeing the other.
   */
  CAMLreturn ((value) xpathobj->nodesetval->nodeTab[i]);
}

value
mllib_xml_xpathctx_set_nodeptr (value xpathctxv, value nodev)
{
  CAMLparam2 (xpathctxv, nodev);
  xmlXPathContextPtr xpathctx = xpathctxptr_val (xpathctxv);
  xmlNodePtr node = (xmlNodePtr) nodev;

  xpathctx->node = node;

  CAMLreturn (Val_unit);
}

value
mllib_xml_nodeptr_name (value nodev)
{
  CAMLparam1 (nodev);
  xmlNodePtr node = (xmlNodePtr) nodev;

  switch (node->type) {
  case XML_ATTRIBUTE_NODE:
  case XML_ELEMENT_NODE:
    CAMLreturn (caml_copy_string ((char *) node->name));

  default:
    caml_invalid_argument ("node_name: don't know how to get the name of this node");
  }
}

value
mllib_xml_nodeptr_as_string (value docv, value nodev)
{
  CAMLparam2 (docv, nodev);
  CAMLlocal1 (strv);
  xmlDocPtr doc = docptr_val (docv);
  xmlNodePtr node = (xmlNodePtr) nodev;
  char *str;

  switch (node->type) {
  case XML_TEXT_NODE:
  case XML_COMMENT_NODE:
  case XML_CDATA_SECTION_NODE:
  case XML_PI_NODE:
    CAMLreturn (caml_copy_string ((char *) node->content));

  case XML_ATTRIBUTE_NODE:
  case XML_ELEMENT_NODE:
    str = (char *) xmlNodeListGetString (doc, node->children, 1);

    if (str == NULL)
      caml_invalid_argument ("node_as_string: xmlNodeListGetString cannot convert node to string");

    strv = caml_copy_string (str);
    free (str);
    CAMLreturn (strv);

  default:
    caml_invalid_argument ("node_as_string: don't know how to convert this node to a string");
  }
}

value
mllib_xml_nodeptr_set_content (value nodev, value contentv)
{
  CAMLparam2 (nodev, contentv);
  xmlNodePtr node = (xmlNodePtr) nodev;

  xmlNodeSetContent (node, BAD_CAST String_val (contentv));

  CAMLreturn (Val_unit);
}

value
mllib_xml_nodeptr_new_text_child (value nodev, value namev, value contentv)
{
  CAMLparam3 (nodev, namev, contentv);
  xmlNodePtr node = (xmlNodePtr) nodev;
  xmlNodePtr new_node;

  new_node = xmlNewTextChild (node, NULL,
                              BAD_CAST String_val (namev),
                              BAD_CAST String_val (contentv));
  if (new_node == NULL)
    caml_invalid_argument ("nodeptr_new_text_child: failed to create new node");

  /* See comment in mllib_xml_xpathobjptr_get_nodeptr about returning
   * named xmlNodePtr here.
   */
  CAMLreturn ((value) new_node);
}

value
mllib_xml_nodeptr_set_prop (value nodev, value namev, value valv)
{
  CAMLparam3 (nodev, namev, valv);
  xmlNodePtr node = (xmlNodePtr) nodev;

  if (xmlSetProp (node,
                  BAD_CAST String_val (namev),
                  BAD_CAST String_val (valv)) == NULL)
    caml_invalid_argument ("nodeptr_set_prop: failed to set property");

  CAMLreturn (Val_unit);
}

value
mllib_xml_nodeptr_unset_prop (value nodev, value namev)
{
  CAMLparam2 (nodev, namev);
  xmlNodePtr node = (xmlNodePtr) nodev;
  int r;

  r = xmlUnsetProp (node, BAD_CAST String_val (namev));

  CAMLreturn (r == 0 ? Val_true : Val_false);
}

value
mllib_xml_nodeptr_unlink_node (value nodev)
{
  CAMLparam1 (nodev);
  xmlNodePtr node = (xmlNodePtr) nodev;

  xmlUnlinkNode (node);
  xmlFreeNode (node);

  CAMLreturn (Val_unit);
}

value
mllib_xml_doc_get_root_element (value docv)
{
  CAMLparam1 (docv);
  CAMLlocal1 (v);
  xmlDocPtr doc = docptr_val (docv);
  xmlNodePtr root;

  root = xmlDocGetRootElement (doc);
  if (root == NULL)
    CAMLreturn (Val_int (0));   /* None */
  else {
    v = caml_alloc (1, 0);
    Store_field (v, 0, (value) root);
    CAMLreturn (v);             /* Some nodeptr */
  }
}

value
mllib_xml_parse_uri (value strv)
{
  CAMLparam1 (strv);
  CAMLlocal3 (rv, sv, ov);
  xmlURIPtr uri;

  uri = xmlParseURI (String_val (strv));
  if (uri == NULL)
    caml_invalid_argument ("parse_uri: unable to parse URI");

  rv = caml_alloc_tuple (9);

  /* field 0: uri_scheme : string option */
  if (uri->scheme) {
    sv = caml_copy_string (uri->scheme);
    ov = caml_alloc (1, 0);
    Store_field (ov, 0, sv);
  }
  else ov = Val_int (0);
  Store_field (rv, 0, ov);

  /* field 1: uri_opaque : string option */
  if (uri->opaque) {
    sv = caml_copy_string (uri->opaque);
    ov = caml_alloc (1, 0);
    Store_field (ov, 0, sv);
  }
  else ov = Val_int (0);
  Store_field (rv, 1, ov);

  /* field 2: uri_authority : string option */
  if (uri->authority) {
    sv = caml_copy_string (uri->authority);
    ov = caml_alloc (1, 0);
    Store_field (ov, 0, sv);
  }
  else ov = Val_int (0);
  Store_field (rv, 2, ov);

  /* field 3: uri_server : string option */
  if (uri->server) {
    sv = caml_copy_string (uri->server);
    ov = caml_alloc (1, 0);
    Store_field (ov, 0, sv);
  }
  else ov = Val_int (0);
  Store_field (rv, 3, ov);

  /* field 4: uri_user : string option */
  if (uri->user) {
    sv = caml_copy_string (uri->user);
    ov = caml_alloc (1, 0);
    Store_field (ov, 0, sv);
  }
  else ov = Val_int (0);
  Store_field (rv, 4, ov);

  /* field 5: uri_port : int */
  Store_field (rv, 5, Val_int (uri->port));

  /* field 6: uri_path : string option */
  if (uri->path) {
    sv = caml_copy_string (uri->path);
    ov = caml_alloc (1, 0);
    Store_field (ov, 0, sv);
  }
  else ov = Val_int (0);
  Store_field (rv, 6, ov);

  /* field 7: uri_fragment : string option */
  if (uri->fragment) {
    sv = caml_copy_string (uri->fragment);
    ov = caml_alloc (1, 0);
    Store_field (ov, 0, sv);
  }
  else ov = Val_int (0);
  Store_field (rv, 7, ov);

  /* field 8: uri_query_raw : string option */
  if (uri->query_raw) {
    sv = caml_copy_string (uri->query_raw);
    ov = caml_alloc (1, 0);
    Store_field (ov, 0, sv);
  }
  else ov = Val_int (0);
  Store_field (rv, 8, ov);

  xmlFreeURI (uri);

  CAMLreturn (rv);
}
