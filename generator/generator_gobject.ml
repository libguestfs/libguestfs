(* libguestfs
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

(* Please read generator/README first. *)

open Str

open Generator_actions
open Generator_docstrings
open Generator_pr
open Generator_structs
open Generator_types
open Generator_utils

let camel_of_name flags name =
  "Guestfs" ^
  try
    find_map (function CamelName n -> Some n | _ -> None) flags
  with Not_found ->
    List.fold_left (
      fun a b ->
        a ^ String.uppercase (Str.first_chars b 1) ^ Str.string_after b 1
    ) "" (Str.split (regexp "_") name)

let generate_gobject_proto name ?(single_line = true)
                                (ret, args, optargs) flags =
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
  pr "guestfs_session_%s(GuestfsSession *session" name;
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
      | String n
      | Device n
      | Pathname n
      | Dev_or_Path n
      | OptString n
      | Key n
      | FileIn n
      | FileOut n ->
        pr "const gchar *%s" n
      | StringList n
      | DeviceList n ->
        pr "gchar *const *%s" n
      | BufferIn n ->
        pr "const guint8 *%s, gsize %s_size" n n
      | Pointer _ ->
        failwith "gobject bindings do not support Pointer arguments"
  ) args;
  if optargs <> [] then (
    pr ", %s *optargs" (camel_of_name flags name)
  );
  (match ret with
  | RBufferOut _ ->
    pr ", gsize *size_r"
  | _ -> ());
  if List.exists (function Cancellable -> true | _ -> false) flags then
    pr ", GCancellable *cancellable";
  pr ", GError **err";
  pr ")"

let generate_gobject_header_static () =
  pr "
#ifndef GUESTFS_GOBJECT_H__
#define GUESTFS_GOBJECT_H__

#include <glib-object.h>
#include <gio/gio.h>

G_BEGIN_DECLS

/* Guestfs::Session object definition */
#define GUESTFS_TYPE_SESSION             (guestfs_session_get_type())
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

typedef struct _GuestfsSession GuestfsSession;
typedef struct _GuestfsSessionClass GuestfsSessionClass;
typedef struct _GuestfsSessionPrivate GuestfsSessionPrivate;

struct _GuestfsSession
{
  GObject parent;
  GuestfsSessionPrivate *priv;
};

struct _GuestfsSessionClass
{
  GObjectClass parent_class;
};

GType guestfs_session_get_type(void);
GuestfsSession *guestfs_session_new(void);
gboolean guestfs_session_close(GuestfsSession *session, GError **err);

/* Guestfs::Tristate */
typedef enum
{
  GUESTFS_TRISTATE_FALSE,
  GUESTFS_TRISTATE_TRUE,
  GUESTFS_TRISTATE_NONE
} GuestfsTristate;

GType guestfs_tristate_get_type(void);
#define GUESTFS_TYPE_TRISTATE (guestfs_tristate_get_type())

"

let generate_gobject_header_static_footer () =
  pr "

G_END_DECLS

#endif /* GUESTFS_GOBJECT_H__ */
"

let generate_gobject_header_structs () =
  pr "/* Structs */\n";
  List.iter (
    fun (typ, cols) ->
      let camel = camel_name_of_struct typ in
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
      pr "GType guestfs_%s_get_type(void);\n\n" typ;
  ) structs

let iter_optargs f =
  List.iter (
    function
    | name, (_, _, (_::_ as optargs)), _, flags,_, _, _ ->
      f name optargs flags
    | _ -> ()
  )

let generate_gobject_header_optarg name optargs flags =
  let uc_name = String.uppercase name in
  let camel_name = camel_of_name flags name in
  let type_define = "GUESTFS_TYPE_" ^ uc_name in

  pr "/* %s */\n" camel_name;

  pr "#define %s " type_define;
  pr "(guestfs_%s_get_type())\n" name;

  pr "#define GUESTFS_%s(obj) " uc_name;
  pr "(G_TYPE_CHECK_INSTANCE_CAST((obj), %s, %s))\n" type_define camel_name;

  pr "#define GUESTFS_%s_CLASS(klass) " uc_name;
  pr "(G_TYPE_CHECK_CLASS_CAST((klass), %s, %sClass))\n" type_define camel_name;

  pr "#define GUESTFS_IS_%s(obj) " uc_name;
  pr "(G_TYPE_CHECK_INSTANCE_TYPE((klass), %s))\n" type_define;

  pr "#define GUESTFS_IS_%s_CLASS(klass) " uc_name;
  pr "(G_TYPE_CHECK_CLASS_TYPE((klass), %s))\n" type_define;

  pr "#define GUESTFS_%s_GET_CLASS(obj) " uc_name;
  pr "(G_TYPE_INSTANCE_GET_CLASS((obj), %s, %sClass))\n" type_define camel_name;

  pr "\n";

  List.iter (
    fun suffix ->
      let name = camel_name ^ suffix in
      pr "typedef struct _%s %s;\n" name name;
  ) [ ""; "Private"; "Class" ];

  pr "\n";

  pr "struct _%s {\n" camel_name;
  pr "  GObject parent;\n";
  pr "  %sPrivate *priv;\n" camel_name;
  pr "};\n\n";

  pr "struct _%sClass {\n" camel_name;
  pr "  GObjectClass parent_class;\n";
  pr "};\n\n";

  pr "GType guestfs_%s_get_type(void);\n" name;
  pr "%s *guestfs_%s_new(void);\n" camel_name name;

  pr "\n"

let generate_gobject_header_optargs () =
  pr "/* Optional arguments */\n\n";
  iter_optargs (
    fun name optargs flags ->
      generate_gobject_header_optarg name optargs flags
  ) all_functions

let generate_gobject_header_methods () =
  pr "/* Generated methods */\n";
  List.iter (
    fun (name, style, _, flags, _, _, _) ->
      generate_gobject_proto name style flags;
      pr ";\n";
  ) all_functions

let generate_gobject_c_static () =
  pr "
#include <glib.h>
#include <glib-object.h>
#include <guestfs.h>
#include <string.h>

#include <stdio.h>

#include \"guestfs-gobject.h\"

/**
 * SECTION: guestfs-session
 * @short_description: Libguestfs session
 * @include: guestfs-gobject.h
 *
 * A libguestfs session which can be used to inspect and modify virtual disk
 * images.
 */

/* Error quark */

#define GUESTFS_ERROR guestfs_error_quark()

static GQuark
guestfs_error_quark(void)
{
  return g_quark_from_static_string(\"guestfs\");
}

#define GUESTFS_SESSION_GET_PRIVATE(obj) (G_TYPE_INSTANCE_GET_PRIVATE ( \
                                            (obj), \
                                            GUESTFS_TYPE_SESSION, \
                                            GuestfsSessionPrivate))

struct _GuestfsSessionPrivate
{
  guestfs_h *g;
};

G_DEFINE_TYPE(GuestfsSession, guestfs_session, G_TYPE_OBJECT);

static void
guestfs_session_finalize(GObject *object)
{
  GuestfsSession *session = GUESTFS_SESSION(object);
  GuestfsSessionPrivate *priv = session->priv;

  if (priv->g) guestfs_close(priv->g);

  G_OBJECT_CLASS(guestfs_session_parent_class)->finalize(object);
}

static void
guestfs_session_class_init(GuestfsSessionClass *klass)
{
  GObjectClass *object_class = G_OBJECT_CLASS(klass);

  object_class->finalize = guestfs_session_finalize;

  g_type_class_add_private(klass, sizeof(GuestfsSessionPrivate));
}

static void
guestfs_session_init(GuestfsSession *session)
{
  session->priv = GUESTFS_SESSION_GET_PRIVATE(session);
  session->priv->g = guestfs_create();
}

/**
 * guestfs_session_new:
 *
 * Create a new libguestfs session.
 *
 * Returns: (transfer full): a new guestfs session object
 */
GuestfsSession *
guestfs_session_new(void)
{
  return GUESTFS_SESSION(g_object_new(GUESTFS_TYPE_SESSION, NULL));
}

/**
 * guestfs_session_close:
 *
 * Close a libguestfs session.
 *
 * Returns: true on success, false on error
 */
gboolean
guestfs_session_close(GuestfsSession *session, GError **err)
{
  guestfs_h *g = session->priv->g;

  if (g == NULL) {
    g_set_error_literal(err, GUESTFS_ERROR, 0, \"session is already closed\");
    return FALSE;
  }

  guestfs_close(g);
  session->priv->g = NULL;

  return TRUE;
}

/* Guestfs::Tristate */
GType
guestfs_tristate_get_type(void)
{
  static GType etype = 0;
  if (etype == 0) {
    static const GEnumValue values[] = {
      { GUESTFS_TRISTATE_FALSE, \"GUESTFS_TRISTATE_FALSE\", \"false\" },
      { GUESTFS_TRISTATE_TRUE,  \"GUESTFS_TRISTATE_TRUE\",  \"true\" },
      { GUESTFS_TRISTATE_NONE,  \"GUESTFS_TRISTATE_NONE\",  \"none\" },
      { 0, NULL, NULL }
    };
    etype = g_enum_register_static(\"GuestfsTristate\", values);
  }
  return etype;
}

/* Cancellation handler */
static void
cancelled_handler(gpointer data)
{
  guestfs_h *g = (guestfs_h *)data;
  guestfs_user_cancel(g);
}

"

let generate_gobject_c_structs () =
  pr "/* Structs */\n\n";
  List.iter (
    fun (typ, cols) ->
      let name = "guestfs_" ^ typ in
      let camel_name = "Guestfs" ^ camel_name_of_struct typ in
      pr "/* %s */\n" camel_name;

      pr "static %s *\n" camel_name;
      pr "%s_copy(%s *src)\n" name camel_name;
      pr "{\n";
      pr "  return g_slice_dup(%s, src);\n" camel_name;
      pr "}\n\n";

      pr "static void\n";
      pr "%s_free(%s *src)\n" name camel_name;
      pr "{\n";
      pr "  g_slice_free(%s, src);\n" camel_name;
      pr "}\n\n";

      pr "G_DEFINE_BOXED_TYPE(%s, %s, %s_copy, %s_free)\n\n"
         camel_name name name name;
  ) structs

let generate_gobject_c_optarg name optargs flags =
  let uc_name = String.uppercase name in
  let camel_name = camel_of_name flags name in
  let type_define = "GUESTFS_TYPE_" ^ uc_name in

  pr "/* %s */\n" camel_name;
  pr "#define GUESTFS_%s_GET_PRIVATE(obj) " uc_name;
  pr "(G_TYPE_INSTANCE_GET_PRIVATE((obj), %s, %sPrivate))\n\n"
    type_define camel_name;

  pr "struct _%sPrivate {\n" camel_name;
  List.iter (
    fun optargt ->
      let name = name_of_optargt optargt in
      let typ = match optargt with
      | OBool n   -> "GuestfsTristate "
      | OInt n    -> "gint "
      | OInt64 n  -> "gint64 "
      | OString n -> "gchar *" in
      pr "  %s%s;\n" typ name;
  ) optargs;
  pr "};\n\n";

  pr "G_DEFINE_TYPE(%s, guestfs_%s, G_TYPE_OBJECT);\n\n" camel_name name;

  pr "enum {\n";
  pr "PROP_GUESTFS_%s_PROP0" uc_name;
  List.iter (
    fun optargt ->
      let uc_optname = String.uppercase (name_of_optargt optargt) in
      pr ",\n  PROP_GUESTFS_%s_%s" uc_name uc_optname;
  ) optargs;
  pr "\n};\n\n";

  pr "static void\nguestfs_%s_set_property" name;
  pr "(GObject *object, guint property_id, const GValue *value, GParamSpec *pspec)\n";
  pr "{\n";
  pr "  %s *self = GUESTFS_%s(object);\n" camel_name uc_name;
  pr "  %sPrivate *priv = self->priv;\n\n" camel_name;

  pr "  switch (property_id) {\n";
  List.iter (
    fun optargt ->
      let optname = name_of_optargt optargt in
      let uc_optname = String.uppercase optname in
      pr "    case PROP_GUESTFS_%s_%s:\n" uc_name uc_optname;
      (match optargt with
      | OString n ->
        pr "      g_free(priv->%s);\n" n;
      | OBool _ | OInt _ | OInt64 _ -> ());
      let set_value_func = match optargt with
      | OBool _   -> "g_value_get_enum"
      | OInt _    -> "g_value_get_int"
      | OInt64 _  -> "g_value_get_int64"
      | OString _ -> "g_value_dup_string"
      in
      pr "      priv->%s = %s(value);\n" optname set_value_func;
      pr "      break;\n\n";
  ) optargs;
  pr "    default:\n";
  pr "      /* Invalid property */\n";
  pr "      G_OBJECT_WARN_INVALID_PROPERTY_ID(object, property_id, pspec);\n";
  pr "  }\n";
  pr "}\n\n";

  pr "static void\nguestfs_%s_get_property" name;
  pr "(GObject *object, guint property_id, GValue *value, GParamSpec *pspec)\n";
  pr "{\n";
  pr "  %s *self = GUESTFS_%s(object);\n" camel_name uc_name;
  pr "  %sPrivate *priv = self->priv;\n\n" camel_name;

  pr "  switch (property_id) {\n";
  List.iter (
    fun optargt ->
      let optname = name_of_optargt optargt in
      let uc_optname = String.uppercase optname in
      pr "    case PROP_GUESTFS_%s_%s:\n" uc_name uc_optname;
      let set_value_func = match optargt with
      | OBool _   -> "enum"
      | OInt _    -> "int"
      | OInt64 _  -> "int64"
      | OString _ -> "string"
      in
      pr "      g_value_set_%s(value, priv->%s);\n" set_value_func optname;
      pr "      break;\n\n";
  ) optargs;
  pr "    default:\n";
  pr "      /* Invalid property */\n";
  pr "      G_OBJECT_WARN_INVALID_PROPERTY_ID(object, property_id, pspec);\n";
  pr "  }\n";
  pr "}\n\n";

  pr "static void\nguestfs_%s_finalize(GObject *object)\n" name;
  pr "{\n";
  pr "  %s *self = GUESTFS_%s(object);\n" camel_name uc_name;
  pr "  %sPrivate *priv = self->priv;\n\n" camel_name;

  List.iter (
    function
    | OString n ->
      pr "  g_free(priv->%s);\n" n
    | OBool _ | OInt _ | OInt64 _ -> ()
  ) optargs;
  pr "\n";

  pr "  G_OBJECT_CLASS(guestfs_%s_parent_class)->finalize(object);\n" name;
  pr "}\n\n";

  pr "static void\nguestfs_%s_class_init(%sClass *klass)\n" name camel_name;
  pr "{\n";
  pr "  GObjectClass *object_class = G_OBJECT_CLASS(klass);\n";
  pr "  GParamSpec *pspec;\n\n";

  pr "  object_class->set_property = guestfs_%s_set_property;\n" name;
  pr "  object_class->get_property = guestfs_%s_get_property;\n\n" name;

  List.iter (
    fun optargt ->
      let optname = name_of_optargt optargt in
      let uc_optname = String.uppercase optname in
      pr "  pspec = ";
      (match optargt with
      | OBool n ->
        pr "g_param_spec_enum(\"%s\", \"%s\", NULL, " optname optname;
        pr "GUESTFS_TYPE_TRISTATE, GUESTFS_TRISTATE_NONE, ";
      | OInt n ->
        pr "g_param_spec_int(\"%s\", \"%s\", NULL, " optname optname;
        pr "G_MININT32, G_MAXINT32, -1, ";
      | OInt64 n ->
        pr "g_param_spec_int64(\"%s\", \"%s\", NULL, " optname optname;
        pr "G_MININT64, G_MAXINT64, -1, ";
      | OString n ->
        pr "g_param_spec_string(\"%s\", \"%s\", NULL, " optname optname;
        pr "NULL, ");
      pr "G_PARAM_CONSTRUCT | G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS);\n";
      pr "  g_object_class_install_property(object_class, ";
      pr "PROP_GUESTFS_%s_%s, pspec);\n\n" uc_name uc_optname;
  ) optargs;

  pr "  object_class->finalize = guestfs_%s_finalize;\n" name;
  pr "  g_type_class_add_private(klass, sizeof(%sPrivate));\n" camel_name;
  pr "}\n\n";

  pr "static void\nguestfs_%s_init(%s *o)\n" name camel_name;
  pr "{\n";
  pr "  o->priv = GUESTFS_%s_GET_PRIVATE(o);\n" uc_name;
  pr "  /* XXX: Find out if gobject already zeroes private structs */\n";
  pr "  memset(o->priv, 0, sizeof(%sPrivate));\n" camel_name;
  pr "}\n\n";

  pr "/**\n";
  pr " * guestfs_%s_new:\n" name;
  pr " *\n";
  pr " * Create a new %s object\n" camel_name;
  pr " *\n";
  pr " * Returns: (transfer full): a new %s object\n" camel_name;
  pr " */\n";
  pr "%s *\n" camel_name;
  pr "guestfs_%s_new(void)\n" name;
  pr "{\n";
  pr "  return GUESTFS_%s(g_object_new(%s, NULL));\n" uc_name type_define;
  pr "}\n\n"

let generate_gobject_c_optargs () =
  pr "/* Optarg objects */\n\n";

  iter_optargs (
    fun name optargs flags ->
      generate_gobject_c_optarg name optargs flags
  ) all_functions

let generate_gobject_c_methods () =
  pr "/* Generated methods */\n\n";

  List.iter (
    fun (name, (ret, args, optargs as style), _, flags, _, shortdesc, longdesc) ->
      let doc = pod2text ~width:60 name longdesc in
      let doc = String.concat "\n * " doc in
      let camel_name = camel_of_name flags name in
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

      List.iter (
        fun argt ->
          pr " * @%s:" (name_of_argt argt);
          (match argt with
          | Bool _ | Int _ | Int64 _ -> ()
          | String _ | Key _ ->
            pr " (transfer none) (type utf8):"
          | OptString _ ->
            pr " (transfer none) (type utf8) (allow-none):"
          | Device _ | Pathname _ | Dev_or_Path _ | FileIn _ | FileOut _ ->
            pr " (transfer none) (type filename):"
          | StringList _ ->
            pr " (transfer none) (array zero-terminated=1) (element-type utf8): an array of strings"
          | DeviceList _ ->
            pr " (transfer none) (array zero-terminated=1) (element-type filename): an array of strings"
          | BufferIn n ->
            pr " (transfer none) (array length=%s_size) (element-type guint8): an array of binary data" n
          | Pointer _ ->
            failwith "gobject bindings do not support Pointer arguments"
          );
          pr "\n";
      ) args;
      if optargs <> [] then
        pr " * @optargs: (transfer none) (allow-none): a %s containing optional arguments\n" camel_name;
      pr " *\n";

      pr " * %s\n" shortdesc;
      pr " *\n";
      pr " * %s\n" doc;

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
      pr " */\n";

      (* The function body *)

      generate_gobject_proto ~single_line:false name style flags;
      pr "\n{\n";

      let cancellable =
        List.exists (function Cancellable -> true | _ -> false) flags
      in
      if cancellable then (
        pr "  /* Check we haven't already been cancelled */\n";
        pr "  if (g_cancellable_set_error_if_cancelled (cancellable, err))\n";
        pr "    return %s;\n\n" gobject_error_return;
      );

      (* Get the guestfs handle, and ensure it isn't closed *)

      pr "  guestfs_h *g = session->priv->g;\n";
      pr "  if (g == NULL) {\n";
      pr "    g_set_error(err, GUESTFS_ERROR, 0,\n";
      pr "                \"attempt to call %%s after the session has been closed\",\n";
      pr "                \"%s\");\n" name;
      pr "    return %s;\n" gobject_error_return;
      pr "  }\n\n";

      (* Optargs *)

      if optargs <> [] then (
        pr "  struct guestfs_%s_argv argv;\n" name;
        pr "  struct guestfs_%s_argv *argvp = NULL;\n\n" name;

        pr "  if (optargs) {\n";
        let uc_prefix = "GUESTFS_" ^ String.uppercase name in
        pr "    argv.bitmask = 0;\n\n";
        let set_property name typ v_typ get_typ unset =
          let uc_name = String.uppercase name in
          pr "    GValue %s_v = {0, };\n" name;
          pr "    g_value_init(&%s_v, %s);\n" name v_typ;
          pr "    g_object_get_property(G_OBJECT(optargs), \"%s\", &%s_v);\n" name name;
          pr "    %s%s = g_value_get_%s(&%s_v);\n" typ name get_typ name;
          pr "    if (%s != %s) {\n" name unset;
          pr "      argv.bitmask |= %s_%s_BITMASK;\n" uc_prefix uc_name;
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
        ) optargs;
        pr "    argvp = &argv;\n";
        pr "  }\n"
      );

      (* libguestfs call *)

      if cancellable then (
        pr "  gulong id = 0;\n";
        pr "  if (cancellable) {\n";
        pr "    id = g_cancellable_connect(cancellable,\n";
        pr "                               G_CALLBACK(cancelled_handler),\n";
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
      let suffix = if optargs <> [] then "_argv" else "" in
      pr "ret = guestfs_%s%s(g" name suffix;
      List.iter (
        fun argt ->
          pr ", ";
          match argt with
          | BufferIn n ->
            pr "%s, %s_size" n n
          | Bool n | Int n | Int64 n | String n | Device n | Pathname n
          | Dev_or_Path n | OptString n | StringList n | DeviceList n
          | Key n | FileIn n | FileOut n ->
            pr "%s" n
          | Pointer _ ->
            failwith "gobject bindings do not support Pointer arguments"
      ) args;
      if is_RBufferOut then pr ", size_r";
      if optargs <> [] then pr ", argvp";
      pr ");\n";

      if cancellable then
        pr "  g_cancellable_disconnect(cancellable, id);\n";

      (* Check return, throw error if necessary, marshall return value *)

      (match errcode_of_ret ret with
      | `CannotReturnError -> ()
      | _ ->
        pr "  if (ret == %s) {\n"
          (match errcode_of_ret ret with
          | `CannotReturnError -> assert false
          | `ErrorIsMinusOne -> "-1"
          | `ErrorIsNULL -> "NULL");
        pr "    g_set_error_literal(err, GUESTFS_ERROR, 0, guestfs_last_error(g));\n";
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
            pr "%sif (%s%s) memcpy(%s%s, %s%s, sizeof(%s%s));\n"
              indent src n dst n src n dst n
          | n, FString ->
            pr "%sif (%s%s) %s%s = g_strdup(%s%s);\n"
              indent src n dst n src n
          | n, FBuffer ->
            pr "%sif (%s%s) {\n" indent src n;
            pr "%s  %s%s = g_byte_array_sized_new(%s%s_len);\n"
              indent dst n src n;
            pr "%s  g_byte_array_append(%s%s, %s%s, %s%s_len);\n"
              indent dst n src n src n;
            pr "%s}\n" indent
        ) (cols_of_struct typ)
      in
      (match ret with
      | RErr ->
        pr "  return TRUE;\n"

      | RInt _ | RInt64 _ | RBool _
      | RConstString _ | RConstOptString _
      | RString _ | RStringList _
      | RBufferOut _ ->
        pr "  return ret;\n"

      | RHashtable _ ->
        pr "  GHashTable *h = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, g_free);\n";
        pr "  char **i = ret;\n";
        pr "  while (*i) {\n";
        pr "    char *key = *i; i++;\n";
        pr "    char *value = *i; i++;\n";
        pr "    g_hash_table_insert(h, key, value);\n";
        pr "  };\n";
        pr "  g_free(ret);\n";
        pr "  return h;\n"

      | RStruct (_, typ) ->
        let struct_name = "Guestfs" ^ camel_name_of_struct typ in
        pr "  %s *s = g_slice_new0(%s);\n" struct_name struct_name;
        gen_copy_struct "  " "ret->" "s->" typ;
        pr "  guestfs_free_%s(ret);\n" typ;
        pr "  return s;\n";

      | RStructList (_, typ) ->
        let struct_name = "Guestfs" ^ camel_name_of_struct typ in
        pr "  %s **l = g_malloc(sizeof(%s*) * (ret->len + 1));\n"
          struct_name struct_name;
        pr "  gsize i;\n";
        pr "  for (i = 0; i < ret->len; i++) {\n";
        pr "    l[i] = g_slice_new0(%s);\n" struct_name;
        gen_copy_struct "    " "ret->val[i]." "l[i]->" typ;
        pr "  }\n";
        pr "  guestfs_free_%s_list(ret);\n" typ;
        pr "  l[i] = NULL;\n";
        pr "  return l;\n";
      );

      pr "}\n\n";
  ) all_functions

let generate_gobject_header () =
  generate_header CStyle GPLv2plus;
  generate_gobject_header_static ();
  generate_gobject_header_structs ();
  generate_gobject_header_optargs ();
  generate_gobject_header_methods ();
  generate_gobject_header_static_footer ()

let generate_gobject_c () =
  generate_header CStyle GPLv2plus;
  generate_gobject_c_static ();
  generate_gobject_c_structs ();
  generate_gobject_c_optargs ();
  generate_gobject_c_methods ();
