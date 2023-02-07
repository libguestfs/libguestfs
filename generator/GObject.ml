(* libguestfs
 * Copyright (C) 2012-2023 Red Hat Inc.
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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

(* Please read generator/README first. *)

(* NB: This is missing support for OStringList. *)

open Printf

open Std_utils
open Actions
open Docstrings
open Events
open Pr
open Structs
open Types
open Utils

let generate_header = generate_header ~inputs:["generator/gobject.ml"]

let camel_of_name { camel_name } = "Guestfs" ^ camel_name

let generate_gobject_proto name ?(single_line = true)
                                (ret, args, optargs) f =
  let spacer = if single_line then " " else "\n" in
  let ptr_spacer = if single_line then "" else "\n" in
  (match ret with
   | RErr ->
      pr "gboolean%s" spacer
   | RInt _ ->
      pr "gint32%s" spacer
   | RInt64 _ ->
      pr "gint64%s" spacer
   | RBool _ ->
      pr "gint8%s" spacer
   | RConstString _
   | RConstOptString _ ->
      pr "const gchar *%s" ptr_spacer
   | RString _ ->
      pr "gchar *%s" ptr_spacer
   | RStringList _ ->
      pr "gchar **%s" ptr_spacer
   | RStruct (_, typ) ->
      let name = camel_name_of_struct typ in
      pr "Guestfs%s *%s" name ptr_spacer
   | RStructList (_, typ) ->
      let name = camel_name_of_struct typ in
      pr "Guestfs%s **%s" name ptr_spacer
   | RHashtable _ ->
      pr "GHashTable *%s" ptr_spacer
   | RBufferOut _ ->
      pr "guint8 *%s" ptr_spacer
  );
  pr "guestfs_session_%s (GuestfsSession *session" name;
  List.iter (
    fun arg ->
      pr ", ";
      match arg with
      | Bool n ->
        pr "gboolean %s" n
      | Int n ->
        pr "gint32 %s" n
      | Int64 n->
        pr "gint64 %s" n
      | String (_, n)
      | OptString n ->
        pr "const gchar *%s" n
      | StringList (_, n) ->
        pr "gchar *const *%s" n
      | BufferIn n ->
        pr "const guint8 *%s, gsize %s_size" n n
      | Pointer (t, n) ->
        pr "void * /* %s */ %s" t n
  ) args;
  if optargs <> [] then (
    pr ", %s *optargs" (camel_of_name f)
  );
  (match ret with
  | RBufferOut _ ->
    pr ", gsize *size_r"
  | _ -> ());
  if f.cancellable then
    pr ", GCancellable *cancellable";
  pr ", GError **err";
  pr ")"

let filenames =
  "session" :: "tristate" ::

  (* structs *)
  List.map (fun { s_name = typ } -> "struct-" ^ typ) external_structs @

  (* optargs *)
  List.map (function { name } -> "optargs-" ^ name) (
    List.filter (
      function
      | { style = _, _, (_::_) } -> true
      | { style = _, _, [] } -> false
    ) (actions |> external_functions |> sort)
  )

let header_start filename =
  generate_header CStyle GPLv2plus;
  let guard = Str.global_replace (Str.regexp "-") "_" filename in
  let guard = "GUESTFS_GOBJECT_" ^ String.uppercase_ascii guard ^ "_H__" in
  pr "#ifndef %s\n" guard;
  pr "#define %s\n" guard;
  pr "
#include <glib-object.h>
#include <gio/gio.h>

#include <guestfs-gobject.h>

G_BEGIN_DECLS
"

and header_end filename =
  let guard = Str.global_replace (Str.regexp "-") "_" filename in
  let guard = "GUESTFS_GOBJECT_" ^ String.uppercase_ascii guard ^ "_H__" in
  pr "
G_END_DECLS

#endif /* %s */
" guard

let source_start ?title ?shortdesc ?longdesc filename =
  generate_header CStyle GPLv2plus;

  pr "#include <config.h>\n\n";
  pr "#include \"guestfs-gobject.h\"\n\n";
  pr "/**\n";
  pr " * SECTION:%s\n" filename;

  (match title with
  | Some title ->
    pr " * @title: %s\n" title
  | _ -> ());

  (match shortdesc with
  | Some desc ->
    pr " * @short_description: %s\n" desc;
  | _ -> ());

  pr " * @include: guestfs-gobject.h\n";

  (match longdesc with
  | Some desc ->
    pr " *\n";
    pr " %s\n" desc
  | _ -> ());

  pr " */\n"

let generate_gobject_makefile () =
  generate_header HashStyle GPLv2plus;
  let headers =
    List.map
      (function n -> sprintf "include/guestfs-gobject/%s.h" n) filenames
  in
  let sources =
    List.map (function n -> sprintf "src/%s.c" n) filenames
  in
  pr "guestfs_gobject_headers= \\\n  include/guestfs-gobject.h \\\n  %s\n\n"
    (String.concat " \\\n  " headers);
  pr "guestfs_gobject_sources= \\\n  %s\n" (String.concat " \\\n  " sources)

let generate_gobject_header () =
  generate_header CStyle GPLv2plus;
  List.iter
    (function f -> pr "#include <guestfs-gobject/%s.h>\n" f)
    filenames

let generate_gobject_struct_header filename typ cols () =
  header_start filename;

  let camel = camel_name_of_struct typ in

  pr "\n";

  pr "/**\n";
  pr " * Guestfs%s:\n" camel;
  List.iter (
    function
    | n, FChar ->
      pr " * @%s: A character\n" n
    | n, FUInt32 ->
      pr " * @%s: An unsigned 32-bit integer\n" n
    | n, FInt32 ->
      pr " * @%s: A signed 32-bit integer\n" n
    | n, (FUInt64|FBytes) ->
      pr " * @%s: An unsigned 64-bit integer\n" n
    | n, FInt64 ->
      pr " * @%s: A signed 64-bit integer\n" n
    | n, FString ->
      pr " * @%s: A NULL-terminated string\n" n
    | n, FBuffer ->
      pr " * @%s: A GByteArray\n" n
    | n, FUUID ->
      pr " * @%s: A 32 byte UUID. Note that this is not NULL-terminated\n" n
    | n, FOptPercent ->
      pr " * @%s: A floating point number. A value between 0 and 100 " n;
      pr "represents a percentage. A value of -1 represents 'not present'\n"
  ) cols;
  pr " */\n";
  pr "typedef struct _Guestfs%s Guestfs%s;\n" camel camel;
  pr "struct _Guestfs%s {\n" camel;
  List.iter (
    function
    | n, FChar ->
      pr "  gchar %s;\n" n
    | n, FUInt32 ->
      pr "  guint32 %s;\n" n
    | n, FInt32 ->
      pr "  gint32 %s;\n" n
    | n, (FUInt64|FBytes) ->
      pr "  guint64 %s;\n" n
    | n, FInt64 ->
      pr "  gint64 %s;\n" n
    | n, FString ->
      pr "  gchar *%s;\n" n
    | n, FBuffer ->
      pr "  GByteArray *%s;\n" n
    | n, FUUID ->
      pr "  /* The next field is NOT nul-terminated, be careful when printing it: */\n";
      pr "  gchar %s[32];\n" n
    | n, FOptPercent ->
      pr "  /* The next field is [0..100] or -1 meaning 'not present': */\n";
      pr "  gfloat %s;\n" n
  ) cols;
  pr "};\n";
  pr "GType guestfs_%s_get_type (void);\n" typ;

  header_end filename

let generate_gobject_struct_source filename typ () =
  let title = "Guestfs" ^ camel_name_of_struct typ in
  source_start ~title filename;

  let name = "guestfs_" ^ typ in
  let camel_name = "Guestfs" ^ camel_name_of_struct typ in

  pr "\n";

  pr "static %s *\n" camel_name;
  pr "%s_copy (%s *src)\n" name camel_name;
  pr "{\n";
  pr "  return g_slice_dup (%s, src);\n" camel_name;
  pr "}\n\n";

  pr "static void\n";
  pr "%s_free (%s *src)\n" name camel_name;
  pr "{\n";
  pr "  g_slice_free (%s, src);\n" camel_name;
  pr "}\n\n";

  pr "G_DEFINE_BOXED_TYPE (%s, %s, %s_copy, %s_free)\n"
     camel_name name name name

let generate_gobject_optargs_header filename name f () =
  header_start filename;
  let uc_name = String.uppercase_ascii name in
  let camel_name = camel_of_name f in
  let type_define = "GUESTFS_TYPE_" ^ uc_name in

  pr "\n";

  pr "#define %s " type_define;
  pr "(guestfs_%s_get_type ())\n" name;

  pr "#define GUESTFS_%s(obj) " uc_name;
  pr "(G_TYPE_CHECK_INSTANCE_CAST ((obj), %s, %s))\n" type_define camel_name;

  pr "#define GUESTFS_%s_CLASS(klass) " uc_name;
  pr "(G_TYPE_CHECK_CLASS_CAST ((klass), %s, %sClass))\n" type_define camel_name;

  pr "#define GUESTFS_IS_%s(obj) " uc_name;
  pr "(G_TYPE_CHECK_INSTANCE_TYPE ((klass), %s))\n" type_define;

  pr "#define GUESTFS_IS_%s_CLASS(klass) " uc_name;
  pr "(G_TYPE_CHECK_CLASS_TYPE ((klass), %s))\n" type_define;

  pr "#define GUESTFS_%s_GET_CLASS(obj) " uc_name;
  pr "(G_TYPE_INSTANCE_GET_CLASS ((obj), %s, %sClass))\n" type_define camel_name;

  pr "\n";
  pr "typedef struct _%sPrivate %sPrivate;\n" camel_name camel_name;
  pr "\n";

  pr "/**\n";
  pr " * %s:\n" camel_name;
  pr " *\n";
  pr " * An object encapsulating optional arguments for guestfs_session_%s.\n" name;
  pr " */\n";
  pr "typedef struct _%s %s;\n" camel_name camel_name;
  pr "struct _%s {\n" camel_name;
  pr "  GObject parent;\n";
  pr "  %sPrivate *priv;\n" camel_name;
  pr "};\n\n";

  pr "/**\n";
  pr " * %sClass:\n" camel_name;
  pr " * @parent_class: The superclass of %sClass\n" camel_name;
  pr " *\n";
  pr " * A class metadata object for %s.\n" camel_name;
  pr " */\n";
  pr "typedef struct _%sClass %sClass;\n" camel_name camel_name;
  pr "struct _%sClass {\n" camel_name;
  pr "  GObjectClass parent_class;\n";
  pr "};\n\n";

  pr "GType guestfs_%s_get_type (void);\n" name;
  pr "%s *guestfs_%s_new (void);\n" camel_name name;
  header_end filename

let generate_gobject_optargs_source filename name optargs f () =
  let desc =
    "An object encapsulating optional arguments for guestfs_session_" ^ name in
  source_start ~shortdesc:desc ~longdesc:desc filename;

  let uc_name = String.uppercase_ascii name in
  let camel_name = camel_of_name f in
  let type_define = "GUESTFS_TYPE_" ^ uc_name in

  pr "\n";
  pr "#include <string.h>\n\n";

  pr "struct _%sPrivate {\n" camel_name;
  List.iter (
    function
    | OBool n   -> pr "  GuestfsTristate %s;\n" n
    | OInt n    -> pr "  gint %s;\n" n
    | OInt64 n  -> pr "  gint64 %s;\n" n
    | OString n -> pr "  gchar *%s;\n" n
    | OStringList _ -> pr "  /* OStringList not implemented yet */\n"
  ) optargs;
  pr "};\n\n";

  pr "G_DEFINE_TYPE_WITH_CODE (%s, guestfs_%s, G_TYPE_OBJECT,\n"
    camel_name name;
  pr "                         G_ADD_PRIVATE (%s));\n\n" camel_name;

  pr "enum {\n";
  pr "  PROP_GUESTFS_%s_PROP0" uc_name;
  List.iter (
    fun optargt ->
      let uc_optname = String.uppercase_ascii (name_of_optargt optargt) in
      pr ",\n  PROP_GUESTFS_%s_%s" uc_name uc_optname;
  ) optargs;
  pr "\n};\n\n";

  pr "static void\nguestfs_%s_set_property" name;
  pr "(GObject *object, guint property_id, const GValue *value, GParamSpec *pspec)\n";
  pr "{\n";
  pr "  %s *self = GUESTFS_%s (object);\n" camel_name uc_name;
  pr "  %sPrivate *priv = self->priv;\n\n" camel_name;

  pr "  switch (property_id) {\n";
  List.iter (
    function OStringList _ -> () (* XXX *)
    | optargt ->
      let optname = name_of_optargt optargt in
      let uc_optname = String.uppercase_ascii optname in
      pr "    case PROP_GUESTFS_%s_%s:\n" uc_name uc_optname;
      (match optargt with
      | OString n ->
        pr "      g_free (priv->%s);\n" n;
      | OBool _ | OInt _ | OInt64 _ -> ()
      | OStringList _ -> () (* XXX *));
      (match optargt with
      | OBool n   -> pr "      priv->%s = g_value_get_enum (value);\n" n
      | OInt n    -> pr "      priv->%s = g_value_get_int (value);\n" n
      | OInt64 n  -> pr "      priv->%s = g_value_get_int64 (value);\n" n
      | OString n -> pr "      priv->%s = g_value_dup_string (value);\n" n
      | OStringList _ -> ()
      );
      pr "      break;\n\n";
  ) optargs;
  pr "    default:\n";
  pr "      /* Invalid property */\n";
  pr "      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, property_id, pspec);\n";
  pr "  }\n";
  pr "}\n\n";

  pr "static void\nguestfs_%s_get_property" name;
  pr "(GObject *object, guint property_id, GValue *value, GParamSpec *pspec)\n";
  pr "{\n";
  pr "  %s *self = GUESTFS_%s (object);\n" camel_name uc_name;
  pr "  %sPrivate *priv = self->priv;\n\n" camel_name;

  pr "  switch (property_id) {\n";
  List.iter (
    function OStringList _ -> () (* XXX *)
    | optargt ->
      let optname = name_of_optargt optargt in
      let uc_optname = String.uppercase_ascii optname in
      pr "    case PROP_GUESTFS_%s_%s:\n" uc_name uc_optname;
      let set_value_func = match optargt with
      | OBool _   -> "enum"
      | OInt _    -> "int"
      | OInt64 _  -> "int64"
      | OString _ -> "string"
      | OStringList _ -> "" (* XXX *)
      in
      pr "      g_value_set_%s (value, priv->%s);\n" set_value_func optname;
      pr "      break;\n\n";
  ) optargs;
  pr "    default:\n";
  pr "      /* Invalid property */\n";
  pr "      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, property_id, pspec);\n";
  pr "  }\n";
  pr "}\n\n";

  pr "static void\nguestfs_%s_finalize (GObject *object)\n" name;
  pr "{\n";

  let needs_priv = List.exists (function
    | OString _ -> true
    | OStringList _ | OBool _ | OInt _ | OInt64 _ -> false
  ) optargs in

  if needs_priv then (
    pr "  %s *self = GUESTFS_%s (object);\n" camel_name uc_name;
    pr "  %sPrivate *priv = self->priv;\n" camel_name;
    pr "\n";
  );

  List.iter (
    function
    | OString n ->
      pr "  g_free (priv->%s);\n" n
    | OStringList n -> () (* XXX *)
    | OBool _ | OInt _ | OInt64 _ -> ()
  ) optargs;

  pr "  G_OBJECT_CLASS (guestfs_%s_parent_class)->finalize (object);\n" name;
  pr "}\n\n";

  pr "static void\nguestfs_%s_class_init (%sClass *klass)\n" name camel_name;
  pr "{\n";
  pr "  GObjectClass *object_class = G_OBJECT_CLASS (klass);\n";

  pr "  object_class->set_property = guestfs_%s_set_property;\n" name;
  pr "  object_class->get_property = guestfs_%s_get_property;\n\n" name;

  List.iter (
    function OStringList _ -> () (* XXX *)
    | optargt ->
      let optname = name_of_optargt optargt in
      let type_spec, type_init, type_desc =
        match optargt with
        | OBool n ->
          "enum", "GUESTFS_TYPE_TRISTATE, GUESTFS_TRISTATE_NONE", "A boolean."
        | OInt n ->
          "int", "G_MININT32, G_MAXINT32, -1", "A 32-bit integer."
        | OInt64 n ->
          "int64", "G_MININT64, G_MAXINT64, -1", "A 64-bit integer."
        | OString n ->
          "string", "NULL", "A string."
        | OStringList n -> "", "", "" (* XXX *)
      in
      pr "  /**\n";
      pr "   * %s:%s:\n" camel_name optname;
      pr "   *\n";
      pr "   * %s\n" type_desc;
      pr "   */\n";
      pr "  g_object_class_install_property (\n";
      pr "    object_class,\n";
      pr "    PROP_GUESTFS_%s_%s,\n" uc_name (String.uppercase_ascii optname);
      pr "    g_param_spec_%s (\n" type_spec;
      pr "      \"%s\",\n" optname;
      pr "      \"%s\",\n" optname;
      pr "      \"%s\",\n" type_desc;
      pr "      %s,\n" type_init;
      pr "      G_PARAM_CONSTRUCT | G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS\n";
      pr "    )\n";
      pr "  );\n\n";

  ) optargs;

  pr "  object_class->finalize = guestfs_%s_finalize;\n" name;
  pr "}\n\n";

  pr "static void\nguestfs_%s_init (%s *o)\n" name camel_name;
  pr "{\n";
  pr "  o->priv = guestfs_%s_get_instance_private (o);\n" name;
  pr "  /* XXX: Find out if gobject already zeroes private structs */\n";
  pr "  memset (o->priv, 0, sizeof (%sPrivate));\n" camel_name;
  pr "}\n\n";

  pr "/**\n";
  pr " * guestfs_%s_new:\n" name;
  pr " *\n";
  pr " * Create a new %s object\n" camel_name;
  pr " *\n";
  pr " * Returns: (transfer full): a new %s object\n" camel_name;
  pr " */\n";
  pr "%s *\n" camel_name;
  pr "guestfs_%s_new (void)\n" name;
  pr "{\n";
  pr "  return GUESTFS_%s (g_object_new (%s, NULL));\n" uc_name type_define;
  pr "}\n"

let generate_gobject_tristate_header () =
  let filename = "tristate" in
  header_start filename;
  pr "
/**
 * GuestfsTristate:
 * @GUESTFS_TRISTATE_FALSE: False
 * @GUESTFS_TRISTATE_TRUE: True
 * @GUESTFS_TRISTATE_NONE: Unset
 *
 * An object representing a tristate: i.e. true, false, or unset. If a language
 * binding has a native concept of true and false which also correspond to the
 * integer values 1 and 0 respectively, these will also correspond to
 * GUESTFS_TRISTATE_TRUE and GUESTFS_TRISTATE_FALSE.
 */
typedef enum
{
  GUESTFS_TRISTATE_FALSE,
  GUESTFS_TRISTATE_TRUE,
  GUESTFS_TRISTATE_NONE
} GuestfsTristate;

GType guestfs_tristate_get_type (void);
#define GUESTFS_TYPE_TRISTATE (guestfs_tristate_get_type ())
";
  header_end filename

let generate_gobject_tristate_source () =
  let filename = "tristate" in
  let title = "GuestfsTristate" in
  let shortdesc = "An object representing a tristate value" in
  source_start ~title ~shortdesc filename;
  pr "
GType
guestfs_tristate_get_type (void)
{
  static GType etype = 0;
  if (etype == 0) {
    static const GEnumValue values[] = {
      { GUESTFS_TRISTATE_FALSE, \"GUESTFS_TRISTATE_FALSE\", \"false\" },
      { GUESTFS_TRISTATE_TRUE,  \"GUESTFS_TRISTATE_TRUE\",  \"true\" },
      { GUESTFS_TRISTATE_NONE,  \"GUESTFS_TRISTATE_NONE\",  \"none\" },
      { 0, NULL, NULL }
    };
    etype = g_enum_register_static (\"GuestfsTristate\", values);
  }
  return etype;
}
"

let generate_gobject_session_header () =
  let filename = "session" in
  header_start filename;
  pr "
/* GuestfsSessionEvent */

/**
 * GuestfsSessionEvent:
";

  List.iter (
    fun (name, _) ->
      pr " * @GUESTFS_SESSION_EVENT_%s: The %s event\n"
        (String.uppercase_ascii name) name;
  ) events;

  pr " *
 * For more detail on libguestfs events, see \"SETTING CALLBACKS TO HANDLE
 * EVENTS\" in guestfs(3).
 */
typedef enum {";

  List.iter (
    fun (name, _) ->
      pr "\n  GUESTFS_SESSION_EVENT_%s," (String.uppercase_ascii name);
  ) events;

  pr "
} GuestfsSessionEvent;
GType guestfs_session_event_get_type (void);
#define GUESTFS_TYPE_SESSION_EVENT (guestfs_session_event_get_type ())

/* GuestfsSessionEventParams */

/**
 * GuestfsSessionEventParams:
 * @event: The event
 * @flags: Unused
 * @buf: A message buffer. This buffer can contain arbitrary 8 bit data,
 *       including NUL bytes
 * @array: An array of 64-bit unsigned integers
 * @array_len: The length of @array
 */
typedef struct _GuestfsSessionEventParams GuestfsSessionEventParams;
struct _GuestfsSessionEventParams {
  GuestfsSessionEvent event;
  guint flags;
  GByteArray *buf;
  /* The libguestfs array has no fixed length, although it is currently only
   * ever empty or length 4. We fix the length of the array here as there is
   * currently no way for an arbitrary length array to be introspected in a
   * boxed object.
   */
  guint64 array[16];
  size_t array_len;
};
GType guestfs_session_event_params_get_type (void);

/* GuestfsSession object definition */
#define GUESTFS_TYPE_SESSION             (guestfs_session_get_type ())
#define GUESTFS_SESSION(obj)             (G_TYPE_CHECK_INSTANCE_CAST ( \
                                          (obj), \
                                          GUESTFS_TYPE_SESSION, \
                                          GuestfsSession))
#define GUESTFS_SESSION_CLASS(klass)     (G_TYPE_CHECK_CLASS_CAST ( \
                                          (klass), \
                                          GUESTFS_TYPE_SESSION, \
                                          GuestfsSessionClass))
#define GUESTFS_IS_SESSION(obj)          (G_TYPE_CHECK_INSTANCE_TYPE ( \
                                          (obj), \
                                          GUESTFS_TYPE_SESSION))
#define GUESTFS_IS_SESSION_CLASS(klass)  (G_TYPE_CHECK_CLASS_TYPE ( \
                                          (klass), \
                                          GUESTFS_TYPE_SESSION))
#define GUESTFS_SESSION_GET_CLASS(obj)   (G_TYPE_INSTANCE_GET_CLASS ( \
                                          (obj), \
                                          GUESTFS_TYPE_SESSION, \
                                          GuestfsSessionClass))

typedef struct _GuestfsSessionPrivate GuestfsSessionPrivate;

/**
 * GuestfsSession:
 *
 * A libguestfs session, encapsulating a single libguestfs handle.
 */
typedef struct _GuestfsSession GuestfsSession;
struct _GuestfsSession
{
  GObject parent;
  GuestfsSessionPrivate *priv;
};

/**
 * GuestfsSessionClass:
 * @parent_class: The superclass of GuestfsSession
 *
 * A class metadata object for GuestfsSession.
 */
typedef struct _GuestfsSessionClass GuestfsSessionClass;
struct _GuestfsSessionClass
{
  GObjectClass parent_class;
};

GType guestfs_session_get_type (void);
GuestfsSession *guestfs_session_new (void);
gboolean guestfs_session_close (GuestfsSession *session, GError **err);

";

  List.iter (
    fun ({ name; style } as f) ->
      generate_gobject_proto name style f;
      pr ";\n";
  ) (actions |> external_functions |> sort);

  header_end filename

let generate_gobject_session_source () =
  let filename = "session" in
  let shortdesc = "A libguestfs session" in
  source_start ~shortdesc filename;

  pr "
/* It is safe to call deprecated functions from this file. */
#define GUESTFS_NO_WARN_DEPRECATED
#undef GUESTFS_NO_DEPRECATED

  #include <glib.h>
  #include <glib-object.h>
  #include <guestfs.h>
  #include <stdint.h>
  #include <stdio.h>
  #include <string.h>
  #include <inttypes.h>

/* Error quark */

#define GUESTFS_ERROR guestfs_error_quark ()

static GQuark
guestfs_error_quark (void)
{
  return g_quark_from_static_string (\"guestfs\");
}

/* Cancellation handler */
static void
cancelled_handler (gpointer data)
{
  guestfs_h *g = (guestfs_h *)data;
  guestfs_user_cancel (g);
}

/* GuestfsSessionEventParams */
static GuestfsSessionEventParams *
guestfs_session_event_params_copy (GuestfsSessionEventParams *src)
{
  return g_slice_dup (GuestfsSessionEventParams, src);
}

static void
guestfs_session_event_params_free (GuestfsSessionEventParams *src)
{
  g_slice_free (GuestfsSessionEventParams, src);
}

G_DEFINE_BOXED_TYPE (GuestfsSessionEventParams,
                    guestfs_session_event_params,
                    guestfs_session_event_params_copy,
                    guestfs_session_event_params_free)

/* Event callback */
";

  pr "static guint signals[%i] = { 0 };\n" (List.length events);

pr "
static GuestfsSessionEvent
guestfs_session_event_from_guestfs_event (uint64_t event)
{
  switch (event) {";

  List.iter (
    fun (name, _) ->
      let enum_name = "GUESTFS_SESSION_EVENT_" ^ String.uppercase_ascii name in
      let guestfs_name = "GUESTFS_EVENT_" ^ String.uppercase_ascii name in
      pr "\n    case %s: return %s;" guestfs_name enum_name;
  ) events;

pr "
  }

  g_warning (\"guestfs_session_event_from_guestfs_event: invalid event %%\" PRIu64,
            event);
  return UINT32_MAX;
}

static void
event_callback (guestfs_h *g, void *opaque,
               uint64_t event, int event_handle,
               int flags,
               const char *buf, size_t buf_len,
               const uint64_t *array, size_t array_len)
{
  GuestfsSessionEventParams *params = g_slice_new0 (GuestfsSessionEventParams);

  params->event = guestfs_session_event_from_guestfs_event (event);
  params->flags = flags;

  params->buf = g_byte_array_sized_new (buf_len);
  g_byte_array_append (params->buf, (const guint8 *) buf, buf_len);

  for (size_t i = 0; i < array_len && i < 4; i++) {
    if (array_len > 4) {
      array_len = 4;
    }
    memcpy (params->array, array, sizeof (array[0]) * array_len);
  }
  params->array_len = array_len;

  GuestfsSession *session = (GuestfsSession *) opaque;

  g_signal_emit (session, signals[params->event], 0, params);

  guestfs_session_event_params_free (params);
}

/* GuestfsSessionEvent */

GType
guestfs_session_event_get_type (void)
{
  static GType etype = 0;
  if (etype == 0) {
    static const GEnumValue values[] = {";

  List.iter (
    fun (name, _) ->
      let enum_name = "GUESTFS_SESSION_EVENT_" ^ String.uppercase_ascii name in
      pr "\n      { %s, \"%s\", \"%s\" }," enum_name enum_name name
  ) events;

  pr "
    };
    etype = g_enum_register_static (\"GuestfsSessionEvent\", values);
  }
  return etype;
}

/* GuestfsSession */

struct _GuestfsSessionPrivate
{
  guestfs_h *g;
  int event_handle;
};

G_DEFINE_TYPE_WITH_CODE (GuestfsSession, guestfs_session, G_TYPE_OBJECT,
                         G_ADD_PRIVATE (GuestfsSession));

static void
guestfs_session_finalize (GObject *object)
{
  GuestfsSession *session = GUESTFS_SESSION (object);
  GuestfsSessionPrivate *priv = session->priv;

  if (priv->g) guestfs_close (priv->g);

  G_OBJECT_CLASS (guestfs_session_parent_class)->finalize (object);
}

static void
guestfs_session_class_init (GuestfsSessionClass *klass)
{
  GObjectClass *object_class = G_OBJECT_CLASS (klass);

  object_class->finalize = guestfs_session_finalize;";

  List.iter (
    fun (name, _) ->
      pr "\n\n";
      pr "  /**\n";
      pr "   * GuestfsSession::%s:\n" name;
      pr "   * @session: The session which emitted the signal\n";
      pr "   * @params: An object containing event parameters\n";
      pr "   *\n";
      pr "   * See \"SETTING CALLBACKS TO HANDLE EVENTS\" in guestfs(3) for\n";
      pr "   * more details about this event.\n";
      pr "   */\n";
      pr "  signals[GUESTFS_SESSION_EVENT_%s] =\n"
         (String.uppercase_ascii name);
      pr "    g_signal_new (g_intern_static_string (\"%s\"),\n" name;
      pr "                 G_OBJECT_CLASS_TYPE (object_class),\n";
      pr "                 G_SIGNAL_RUN_LAST,\n";
      pr "                 0,\n";
      pr "                 NULL, NULL,\n";
      pr "                 NULL,\n";
      pr "                 G_TYPE_NONE,\n";
      pr "                 1, guestfs_session_event_params_get_type ());";
  ) events;

  pr "
}

static void
guestfs_session_init (GuestfsSession *session)
{
  session->priv = guestfs_session_get_instance_private (session);
  session->priv->g = guestfs_create ();

  guestfs_h *g = session->priv->g;

  session->priv->event_handle =
    guestfs_set_event_callback (g, event_callback, GUESTFS_EVENT_ALL,
                               0, session);
}

/**
 * guestfs_session_new:
 *
 * Create a new libguestfs session.
 *
 * Returns: (transfer full): a new guestfs session object
 */
GuestfsSession *
guestfs_session_new (void)
{
  return GUESTFS_SESSION (g_object_new (GUESTFS_TYPE_SESSION, NULL));
}

/**
 * guestfs_session_close:
 * @session: (transfer none): A GuestfsSession object
 * @err: A GError object to receive any generated errors
 *
 * Close a libguestfs session.
 *
 * Returns: true on success, false on error
 */
gboolean
guestfs_session_close (GuestfsSession *session, GError **err)
{
  guestfs_h *g = session->priv->g;

  if (g == NULL) {
    g_set_error_literal (err, GUESTFS_ERROR, 0, \"session is already closed\");
    return FALSE;
  }

  guestfs_close (g);
  session->priv->g = NULL;

  return TRUE;
}";

  let urls = Str.regexp "L<\\(https?\\)://\\([^>]*\\)>" in
  let bz = Str.regexp "RHBZ#\\([0-9]+\\)" in
  let cve = Str.regexp "\\(\\s\\)\\(CVE-[0-9]+-[0-9]+\\)" in
  let api_crossref = Str.regexp "C<guestfs_\\([-_0-9a-zA-Z]+\\)>" in
  let nonapi_crossref = Str.regexp "C<\\([-_0-9a-zA-Z]+\\)>" in
  let escaped = Str.regexp "E<\\([0-9a-zA-Z]+\\)>" in
  let literal = Str.regexp "\\(^\\|\n\\)[ \t]+\\([^\n]*\\)\\(\n\\|$\\)" in

  List.iter (
    fun ({ name; style = (ret, args, optargs as style);
           cancellable; c_function; c_optarg_prefix;
           shortdesc; longdesc;
           deprecated_by } as f) ->
      pr "\n";

      let longdesc = Str.global_substitute urls (
          fun s ->
            let scheme = Str.matched_group 1 s in
            let url = Str.matched_group 2 s in
            (* The spaces below are deliberate: they give pod2text somewhere to
               split that isn't the middle of a URL. *)
            "<ulink url='" ^ scheme ^ "://" ^ url ^
              "'> http://" ^ url ^ " </ulink>"
        ) longdesc in
      let longdesc = Str.global_substitute bz (
          fun s ->
            let bz = Str.matched_group 1 s in
            (* The spaces below are deliberate: they give pod2text somewhere to
               split that isn't the middle of a URL. *)
            "<ulink url='https://bugzilla.redhat.com/show_bug.cgi?id=" ^
              bz ^ "'> RHBZ&num;" ^ bz ^ " </ulink>"
        ) longdesc in
      let longdesc = Str.global_substitute cve (
          fun s ->
            let space_lead = Str.matched_group 1 s in
            let cve = Str.matched_group 2 s in
            (* The spaces below are deliberate: they give pod2text somewhere to
               split that isn't the middle of a URL. *)
            space_lead ^
            "<ulink url='https://cve.mitre.org/cgi-bin/cvename.cgi?name=" ^
            cve ^ "'> " ^ cve ^ " </ulink>"
        ) longdesc in
      let longdesc = Str.global_substitute api_crossref (
          fun s ->
            "guestfs_session_" ^ Str.matched_group 1 s ^ "()"
        ) longdesc in
      let longdesc = Str.global_substitute nonapi_crossref (
          fun s ->
            "@" ^ Str.matched_group 1 s
        ) longdesc in
      let longdesc = Str.global_substitute escaped (
          fun s ->
            "&" ^ Str.matched_group 1 s ^ ";"
        ) longdesc in
      let longdesc = Str.global_substitute literal (
          fun s ->
            "\n <![CDATA[" ^ Str.matched_group 2 s ^ "]]>\n"
        ) longdesc in
      let doc = pod2text ~width:76 name longdesc in
      let doc = String.concat "\n * " doc in
      let camel_name = camel_of_name f in
      let is_RBufferOut = match ret with RBufferOut _ -> true | _ -> false in
      let gobject_error_return = match ret with
      | RErr ->
        "FALSE"
      | RInt _ | RInt64 _ | RBool _ ->
        "-1"
      | RConstString _ | RString _ | RStringList _ | RHashtable _
      | RBufferOut _ | RStruct _ | RStructList _ ->
        "NULL"
      | RConstOptString _ ->
        "NULL" (* NULL is a valid return for RConstOptString. Error is
                  indicated by also setting *err to a non-NULL value *)
      in

      (* The comment header, including GI annotations for arguments and the
      return value *)

      pr "/**\n";
      pr " * guestfs_session_%s:\n" name;
      pr " * @session: (transfer none): A GuestfsSession object\n";

      List.iter (
        fun argt ->
          pr " * @%s:" (name_of_argt argt);
          (match argt with
          | Bool _ ->
            pr " (type gboolean):"
          | Int _ ->
            pr " (type gint32):"
          | Int64 _ ->
            pr " (type gint64):"
          | String ((PlainString|Key|GUID), _) ->
            pr " (transfer none) (type utf8):"
          | OptString _ ->
            pr " (transfer none) (type utf8) (allow-none):"
          | String ((Device|Mountable|Pathname|Filename
                     |Dev_or_Path|Mountable_or_Path|FileIn|FileOut), _) ->
            pr " (transfer none) (type filename):"
          | StringList ((PlainString|Key|GUID), _) ->
            pr " (transfer none) (array zero-terminated=1) (element-type utf8): an array of strings"
          | StringList ((Device|Mountable|Pathname|Filename
                         |Dev_or_Path|Mountable_or_Path|FileIn|FileOut), _) ->
            pr " (transfer none) (array zero-terminated=1) (element-type filename): an array of strings"
          | BufferIn n ->
            pr " (transfer none) (array length=%s_size) (element-type guint8): an array of binary data\n" n;
            pr " * @%s_size: The size of %s, in bytes" n n;
          | Pointer _ ->
            pr "pointer (not implemented in gobject bindings)"
          );
          pr "\n";
      ) args;
      if optargs <> [] then
        pr " * @optargs: (transfer none) (allow-none): a %s containing optional arguments\n" camel_name;
      (match ret with
      | RBufferOut _ ->
        pr " * @size_r: The size of the returned buffer, in bytes\n";
      | _ -> ());
      if cancellable then (
        pr " * @cancellable: A GCancellable object\n";
      );
      pr " * @err: A GError object to receive any generated errors\n";
      pr " *\n";

      pr " * %s\n" shortdesc;
      pr " *\n";
      pr " * %s\n" doc;

      (match f.optional with
      | None -> ()
      | Some opt ->
        pr " * This function depends on the feature \"%s\".\n" opt;
        pr " * See also guestfs_session_feature_available().\n";
        pr " *\n";
      );

      pr " * Returns: ";
      (match ret with
      | RErr ->
        pr "true on success, false on error"
      | RInt _ | RInt64 _ | RBool _ ->
        pr "the returned value, or -1 on error"
      | RConstString _ ->
        pr "(transfer none): the returned string, or NULL on error"
      | RConstOptString _ ->
        pr "(transfer none): the returned string. Note that NULL does not indicate error"
      | RString _ ->
        pr "(transfer full): the returned string, or NULL on error"
      | RStringList _ ->
        pr "(transfer full) (array zero-terminated=1) (element-type utf8): an array of returned strings, or NULL on error"
      | RHashtable _ ->
        pr "(transfer full) (element-type utf8 utf8): a GHashTable of results, or NULL on error"
      | RBufferOut _ ->
        pr "(transfer full) (array length=size_r) (element-type guint8): an array of binary data, or NULL on error"
      | RStruct (_, typ) ->
         let name = camel_name_of_struct typ in
         pr "(transfer full): a %s object, or NULL on error" name
      | RStructList (_, typ) ->
         let name = camel_name_of_struct typ in
         pr "(transfer full) (array zero-terminated=1) (element-type Guestfs%s): an array of %s objects, or NULL on error" name name
      );
      pr "\n";
      (match deprecated_by with
      | Not_deprecated -> ()
      | Replaced_by alt ->
        pr " * Deprecated: In new code, use guestfs_session_%s() instead\n" alt
      | Deprecated_no_replacement ->
        pr " * Deprecated: There is no documented replacement\n"
      );
      (match version_added f with
      | None -> ()
      | Some version -> pr " * Since: %s\n" version
      );
      pr " */\n";

      (* The function body *)

      generate_gobject_proto ~single_line:false name style f;
      pr "\n{\n";

      if cancellable then (
        pr "  /* Check we haven't already been cancelled */\n";
        pr "  if (g_cancellable_set_error_if_cancelled (cancellable, err))\n";
        pr "    return %s;\n\n" gobject_error_return;
      );

      (* Get the guestfs handle, and ensure it isn't closed *)

      pr "  guestfs_h *g = session->priv->g;\n";
      pr "  if (g == NULL) {\n";
      pr "    g_set_error (err, GUESTFS_ERROR, 0,\n";
      pr "                \"attempt to call %%s after the session has been closed\",\n";
      pr "                \"%s\");\n" name;
      pr "    return %s;\n" gobject_error_return;
      pr "  }\n\n";

      (* Optargs *)

      if optargs <> [] then (
        pr "  struct %s argv;\n" c_function;
        pr "  struct %s *argvp = NULL;\n\n" c_function;

        pr "  if (optargs) {\n";
        pr "    argv.bitmask = 0;\n\n";
        let set_property name typ v_typ get_typ unset =
          let uc_name = String.uppercase_ascii name in
          pr "    GValue %s_v = {0, };\n" name;
          pr "    g_value_init (&%s_v, %s);\n" name v_typ;
          pr "    g_object_get_property (G_OBJECT (optargs), \"%s\", &%s_v);\n" name name;
          pr "    %s%s = g_value_get_%s (&%s_v);\n" typ name get_typ name;
          pr "    if (%s != %s) {\n" name unset;
          pr "      argv.bitmask |= %s_%s_BITMASK;\n" c_optarg_prefix uc_name;
          pr "      argv.%s = %s;\n" name name;
          pr "    }\n"
        in
        List.iter (
          function
          | OBool n ->
            set_property n "GuestfsTristate " "GUESTFS_TYPE_TRISTATE" "enum" "GUESTFS_TRISTATE_NONE"
          | OInt n ->
            set_property n "gint32 " "G_TYPE_INT" "int" "-1"
          | OInt64 n ->
            set_property n "gint64 " "G_TYPE_INT64" "int64" "-1"
          | OString n ->
            set_property n "const gchar *" "G_TYPE_STRING" "string" "NULL"
          | OStringList n ->
            () (* XXX *)
        ) optargs;
        pr "    argvp = &argv;\n";
        pr "  }\n"
      );

      (* libguestfs call *)

      if cancellable then (
        pr "  gulong id = 0;\n";
        pr "  if (cancellable) {\n";
        pr "    id = g_cancellable_connect (cancellable,\n";
        pr "                               G_CALLBACK (cancelled_handler),\n";
        pr "                               g, NULL);\n";
        pr "  }\n\n";
      );

      pr "  ";
      (match ret with
      | RErr | RInt _ | RBool _ ->
        pr "int "
      | RInt64 _ ->
        pr "int64_t "
      | RConstString _ | RConstOptString _ ->
        pr "const char *"
      | RString _ | RBufferOut _ ->
        pr "char *"
      | RStringList _ | RHashtable _ ->
        pr "char **"
      | RStruct (_, typ) ->
        pr "struct guestfs_%s *" typ
      | RStructList (_, typ) ->
        pr "struct guestfs_%s_list *" typ
      );
      pr "ret = %s (g" c_function;
      List.iter (
        fun argt ->
          pr ", ";
          match argt with
          | BufferIn n ->
            pr "(const char *) %s, %s_size" n n
          | Bool n | Int n | Int64 n
          | String (_, n)
          | OptString n
          | StringList (_, n) ->
            pr "%s" n
          | Pointer (_, n) ->
            pr "%s" n
      ) args;
      if is_RBufferOut then pr ", size_r";
      if optargs <> [] then pr ", argvp";
      pr ");\n";

      if cancellable then
        pr "  g_cancellable_disconnect (cancellable, id);\n";

      (* Check return, throw error if necessary, marshall return value *)

      (match errcode_of_ret ret with
      | `CannotReturnError -> ()
      | _ ->
        pr "  if (ret == %s) {\n"
          (match errcode_of_ret ret with
          | `CannotReturnError -> assert false
          | `ErrorIsMinusOne -> "-1"
          | `ErrorIsNULL -> "NULL");
        pr "    g_set_error_literal (err, GUESTFS_ERROR, 0, guestfs_last_error (g));\n";
        pr "    return %s;\n" gobject_error_return;
        pr "  }\n";
      );
      pr "\n";

      let gen_copy_struct indent src dst typ =
        List.iter (
          function
          | n, (FChar|FUInt32|FInt32|FUInt64|FBytes|FInt64|FOptPercent) ->
            pr "%s%s%s = %s%s;\n" indent dst n src n
          | n, FUUID ->
            pr "%smemcpy (%s%s, %s%s, sizeof (%s%s));\n"
              indent dst n src n dst n
          | n, FString ->
            pr "%sif (%s%s) %s%s = g_strdup (%s%s);\n"
              indent src n dst n src n
          | n, FBuffer ->
            pr "%sif (%s%s) {\n" indent src n;
            pr "%s  %s%s = g_byte_array_sized_new (%s%s_len);\n"
              indent dst n src n;
            pr "%s  g_byte_array_append (%s%s, (const guint8 *) %s%s, %s%s_len);\n"
              indent dst n src n src n;
            pr "%s}\n" indent
        ) (cols_of_struct typ)
      in
      (match ret with
      | RErr ->
        pr "  return TRUE;\n"

      | RInt _ | RInt64 _ | RBool _
      | RConstString _ | RConstOptString _
      | RString _ | RStringList _ ->
        pr "  return ret;\n"

      | RBufferOut _ ->
        pr "  return (guint8 *) ret;\n"

      | RHashtable _ ->
        pr "  GHashTable *h = g_hash_table_new_full (g_str_hash, g_str_equal, g_free, g_free);\n";
        pr "  char **i = ret;\n";
        pr "  while (*i) {\n";
        pr "    char *key = *i; i++;\n";
        pr "    char *value = *i; i++;\n";
        pr "    g_hash_table_insert (h, key, value);\n";
        pr "  };\n";
        pr "  g_free (ret);\n";
        pr "  return h;\n"

      | RStruct (_, typ) ->
        let struct_name = "Guestfs" ^ camel_name_of_struct typ in
        pr "  %s *s = g_slice_new0 (%s);\n" struct_name struct_name;
        gen_copy_struct "  " "ret->" "s->" typ;
        pr "  guestfs_free_%s (ret);\n" typ;
        pr "  return s;\n";

      | RStructList (_, typ) ->
        let struct_name = "Guestfs" ^ camel_name_of_struct typ in
        pr "  %s **l = g_malloc (sizeof (%s*) * (ret->len + 1));\n"
          struct_name struct_name;
        pr "  gsize i;\n";
        pr "  for (i = 0; i < ret->len; i++) {\n";
        pr "    l[i] = g_slice_new0 (%s);\n" struct_name;
        gen_copy_struct "    " "ret->val[i]." "l[i]->" typ;
        pr "  }\n";
        pr "  guestfs_free_%s_list (ret);\n" typ;
        pr "  l[i] = NULL;\n";
        pr "  return l;\n";
      );

      pr "}\n";
  ) (actions |> external_functions |> sort)
