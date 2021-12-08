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

open Printf

open Std_utils
open Types
open Utils
open Pr
open Docstrings
open Optgroups
open Actions
open Structs
open C
open Events

let generate_header = generate_header ~inputs:["generator/lua.ml"]

let generate_lua_c () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <config.h>

/* It is safe to call deprecated functions from this file. */
#define GUESTFS_NO_WARN_DEPRECATED
#undef GUESTFS_NO_DEPRECATED

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <string.h>
#include <errno.h>
#include <assert.h>

/*#define LUA_LIB*/
#include <lua.h>
#include <lauxlib.h>

#if LUA_VERSION_NUM >= 502
#ifndef lua_objlen
#define lua_objlen lua_rawlen
#endif
#endif

#if LUA_VERSION_NUM >= 503
#ifndef luaL_checkint
#define luaL_checkint(L,n) ((int)luaL_checkinteger(L, (n)))
#endif
#endif

#include \"ignore-value.h\"

#include <guestfs.h>
#include \"guestfs-utils.h\"

#define GUESTFS_LUA_HANDLE \"guestfs handle\"

/* This struct is managed on the Lua heap.  If the GC collects it,
 * the Lua '__gc' function is called which ends up calling
 * guestfs_int_lua_finalizer.
 *
 * There is also an entry in the Lua registry, indexed by 'g'
 * (allocated on demand) which stores per-handle Lua data.  See
 * functions 'get_per_handle_table', 'free_per_handle_table'.
 */
struct userdata {
  guestfs_h *g;          /* Libguestfs handle, NULL if closed. */
  struct event_state *es;
};

/* Structure passed to event_callback_wrapper. */
struct event_state {
  struct event_state *next;             /* Stored in a linked list. */
  lua_State *L;
  struct userdata *u;
  int ref;                              /* Reference to closure. */
};

static struct userdata *get_handle (lua_State *L, int index);

static void get_per_handle_table (lua_State *L, guestfs_h *g);
static void free_per_handle_table (lua_State *L, guestfs_h *g);

static char **get_string_list (lua_State *L, int index);
static void push_string_list (lua_State *L, char **strs);
static void push_table (lua_State *L, char **table);
static int64_t get_int64 (lua_State *L, int index);
static void push_int64 (lua_State *L, int64_t i64);
static void push_int64_array (lua_State *L, const int64_t *array, size_t len);

static void print_any (lua_State *L, int index, FILE *out);

static void event_callback_wrapper (guestfs_h *g, void *esvp, uint64_t event, int eh, int flags, const char *buf, size_t buf_len, const uint64_t *array, size_t array_len);
static uint64_t get_event (lua_State *L, int index);
static uint64_t get_event_bitmask (lua_State *L, int index);
static void push_event (lua_State *L, uint64_t event);

";

  List.iter (
    function
    | typ, RStructOnly ->
      pr "static void push_%s (lua_State *L, struct guestfs_%s *v);\n" typ typ;
    | typ, (RStructListOnly | RStructAndList) ->
      pr "static void push_%s (lua_State *L, struct guestfs_%s *v);\n" typ typ;
      pr "static void push_%s_list (lua_State *L, struct guestfs_%s_list *v);\n" typ typ
  ) (rstructs_used_by (actions |> external_functions));

  pr "\

/* On the stack at 'index' should be a table.  Check if 'name' (string)
 * is a key in this table, and if so execute 'code'.  While 'code' is
 * executing, the top of stack (ie. index == -1) is the value of 'name'.
 */
#define OPTARG_IF_SET(index, name, code) \\
  do {                                   \\
    lua_pushliteral (L, name);           \\
    lua_gettable (L, index);             \\
    if (!lua_isnil (L, -1)) {            \\
      code                               \\
    }                                    \\
    lua_pop (L, 1);                      \\
  } while (0)

/* Create a new connection. */
static int
guestfs_int_lua_create (lua_State *L)
{
  guestfs_h *g;
  struct userdata *u;
  unsigned flags = 0;
  char err[256];

  if (lua_gettop (L) == 1) {
    OPTARG_IF_SET (1, \"environment\",
        if (! lua_toboolean (L, -1))
            flags |= GUESTFS_CREATE_NO_ENVIRONMENT;
    );
    OPTARG_IF_SET (1, \"close_on_exit\",
        if (! lua_toboolean (L, -1))
            flags |= GUESTFS_CREATE_NO_CLOSE_ON_EXIT;
    );
  }
  else if (lua_gettop (L) > 1)
    return luaL_error (L, \"Guestfs.create: too many arguments\");

  g = guestfs_create_flags (flags);
  if (!g)
    return luaL_error (L, \"Guestfs.create: cannot create handle: %%s\",
                       guestfs_int_strerror (errno, err, sizeof err));

  guestfs_set_error_handler (g, NULL, NULL);

  u = lua_newuserdata (L, sizeof (struct userdata));
  luaL_getmetatable (L, GUESTFS_LUA_HANDLE);
  assert (lua_type (L, -1) == LUA_TTABLE);
  lua_setmetatable (L, -2);

  u->g = g;
  u->es = NULL;

  return 1;
}

static void
close_handle (lua_State *L, guestfs_h *g)
{
  guestfs_close (g);
  /* There is a potential and hard-to-solve race here: If another
   * thread allocates another 'g' at the same address, then
   * get_per_handle_table might be called with the same address
   * before we call free_per_handle_table here.  XXX
   */
  free_per_handle_table (L, g);
}

/* Finalizer. */
static int
guestfs_int_lua_finalizer (lua_State *L)
{
  struct userdata *u = get_handle (L, 1);
  struct event_state *es, *es_next;

  if (u->g)
    close_handle (L, u->g);

  for (es = u->es; es != NULL; es = es_next) {
    es_next = es->next;
    free (es);
  }

  /* u will be freed by Lua when we return. */

  return 0;
}

/* Explicit close. */
static int
guestfs_int_lua_close (lua_State *L)
{
  struct userdata *u = get_handle (L, 1);

  if (u->g) {
    close_handle (L, u->g);
    u->g = NULL;
  }

  return 0;
}

/* __tostring function attached to all exceptions. */
static int
error__tostring (lua_State *L)
{
  int code;
  const char *msg;
  char err[256];

  lua_pushliteral (L, \"code\");
  lua_gettable (L, 1);
  code = luaL_checkint (L, -1);
  lua_pushliteral (L, \"msg\");
  lua_gettable (L, 1);
  msg = luaL_checkstring (L, -1);

  if (code)
    lua_pushfstring (L, \"%%s: %%s\", msg,
                     guestfs_int_strerror (code, err, sizeof err));
  else
    lua_pushstring (L, msg);

  return 1;
}

/* Return the last error in the handle. */
static int
last_error (lua_State *L, guestfs_h *g)
{
  /* Construct an error object on the stack containing 'msg'
   * and 'code' fields.
   */
  lua_newtable (L);
  lua_pushliteral (L, \"msg\");
  lua_pushstring (L, guestfs_last_error (g));
  lua_settable (L, -3);
  lua_pushliteral (L, \"code\");
  lua_pushinteger (L, guestfs_last_errno (g));
  lua_settable (L, -3);

  lua_newtable (L);
  lua_pushliteral (L, \"__tostring\");
  lua_pushcfunction (L, error__tostring);
  lua_settable (L, -3);

  lua_setmetatable (L, -2);

  /* Raise an exception with the error object. */
  return lua_error (L);
}

/* Push the per-handle Lua table onto the stack.  This is stored
 * in the global Lua registry.  It is allocated on demand the first
 * time you call this function.  Use luaL_ref to allocate new
 * entries in this table.
 * See also: http://www.lua.org/pil/27.3.1.html
 */
static void
get_per_handle_table (lua_State *L, guestfs_h *g)
{
 again:
  lua_pushlightuserdata (L, g);
  lua_gettable (L, LUA_REGISTRYINDEX);
  if (lua_isnil (L, -1)) {
    lua_pop (L, 1);
    /* registry[g] = {} */
    lua_pushlightuserdata (L, g);
    lua_newtable (L);
    lua_settable (L, LUA_REGISTRYINDEX);
    goto again;
  }
}

/* Free the per-handle Lua table.  It doesn't literally \"free\"
 * anything since the GC will do that.  It just removes the entry
 * from the global registry.
 */
static void
free_per_handle_table (lua_State *L, guestfs_h *g)
{
  /* registry[g] = nil */
  lua_pushlightuserdata (L, g);
  lua_pushnil (L);
  lua_settable (L, LUA_REGISTRYINDEX);
}

/* Set an event callback. */
static int
guestfs_int_lua_set_event_callback (lua_State *L)
{
  struct userdata *u = get_handle (L, 1);
  guestfs_h *g = u->g;
  uint64_t event_bitmask;
  int eh;
  int ref;
  struct event_state *es;

  if (g == NULL)
    return luaL_error (L, \"Guestfs.%%s: handle is closed\",
                       \"set_event_callback\");

  event_bitmask = get_event_bitmask (L, 3);

  /* Save the function in the per-handle table, so that the GC doesn't
   * clean it up before the event fires.
   */
  luaL_checktype (L, 2, LUA_TFUNCTION);
  get_per_handle_table (L, g);
  lua_pushvalue (L, 2);
  ref = luaL_ref (L, -2);
  lua_pop (L, 1);

  es = malloc (sizeof *es);
  if (!es)
    return luaL_error (L, \"failed to allocate event_state\");
  es->next = u->es;
  es->L = L;
  es->u = u;
  es->ref = ref;
  u->es = es;

  eh = guestfs_set_event_callback (g, event_callback_wrapper,
                                   event_bitmask, 0, es);
  if (eh == -1)
    return last_error (L, g);

  /* Return the event handle. */
  lua_pushinteger (L, eh);
  return 1;
}

static void
event_callback_wrapper (guestfs_h *g,
                        void *esvp,
                        uint64_t event,
                        int eh,
                        int flags,
                        const char *buf, size_t buf_len,
                        const uint64_t *array, size_t array_len)
{
  struct event_state *es = esvp;
  lua_State *L = es->L;
  struct userdata *u = es->u;

  /* Look up the closure to call in the per-handle table. */
  get_per_handle_table (L, g);
  lua_rawgeti (L, -1, es->ref);

  if (!lua_isfunction (L, -1)) {
    fprintf (stderr, \"lua-guestfs: %%s: internal error: no closure found for g = %%p, eh = %%d\\n\",
             __func__, g, eh);
    goto out;
  }

  /* Call the event handler: event_handler (g, event, eh, flags, buf, array) */
  /* XXX 'g' parameter is wrong, but fixing it is rather complex.  See:
   * http://article.gmane.org/gmane.comp.lang.lua.general/95051
   */
  lua_pushlightuserdata (L, u);
  push_event (L, event);
  lua_pushinteger (L, eh);
  lua_pushinteger (L, flags);
  lua_pushlstring (L, buf, buf_len);
  push_int64_array (L, (const int64_t *) array, array_len);

  switch (lua_pcall (L, 6, 0, 0)) {
  case 0: /* call ok - do nothing */
    break;
  case LUA_ERRRUN:
    fprintf (stderr, \"lua-guestfs: %%s: unexpected error in event handler: \",
             __func__);
    print_any (L, -1, stderr);
    lua_pop (L, 1);
    fprintf (stderr, \"\\n\");
    break;
  case LUA_ERRERR: /* can probably never happen */
    fprintf (stderr, \"lua-guestfs: %%s: error calling error handler\\n\",
             __func__);
    break;
  case LUA_ERRMEM:
    fprintf (stderr, \"lua-guestfs: %%s: memory allocation failed\\n\", __func__);
    break;
  default:
    fprintf (stderr, \"lua-guestfs: %%s: unknown error\\n\", __func__);
  }

  /* Pop the per-handle table. */
 out:
  lua_pop (L, 1);
}

/* Delete an event callback. */
static int
guestfs_int_lua_delete_event_callback (lua_State *L)
{
  struct userdata *u = get_handle (L, 1);
  guestfs_h *g = u->g;
  int eh;

  if (g == NULL)
    return luaL_error (L, \"Guestfs.%%s: handle is closed\",
                       \"delete_event_callback\");

  eh = luaL_checkint (L, 2);

  guestfs_delete_event_callback (g, eh);

  return 0;
}

";

  (* Actions. *)
  List.iter (
    fun { name; style = (ret, args, optargs as style);
          c_function; c_optarg_prefix } ->
      pr "static int\n";
      pr "guestfs_int_lua_%s (lua_State *L)\n" name;
      pr "{\n";

      (match ret with
      | RErr ->
        pr "  int r;\n";
      | RInt _
      | RBool _ ->
        pr "  int r;\n";
      | RInt64 _ ->
        pr "  int64_t r;\n";
      | RConstString _ ->
        pr "  const char *r;\n";
      | RConstOptString _ ->
        pr "  const char *r;\n";
      | RString _ ->
        pr "  char *r;\n";
      | RStringList _ | RHashtable _ ->
        pr "  char **r;\n";
      | RStruct (_, typ) ->
        pr "  struct guestfs_%s *r;\n" typ;
      | RStructList (_, typ) ->
        pr "  struct guestfs_%s_list *r;\n" typ;
      | RBufferOut _ ->
        pr "  char *r;\n";
        pr "  size_t size;\n";
      );

      (* Handle, arguments. *)
      pr "  struct userdata *u = get_handle (L, 1);\n";
      pr "  guestfs_h *g = u->g;\n";

      List.iter (
        function
        | String (_, n) ->
          pr "  const char *%s;\n" n
        | BufferIn n ->
          pr "  const char *%s;\n" n;
          pr "  size_t %s_size;\n" n;
        | OptString n ->
          pr "  const char *%s;\n" n;
        | StringList (_, n) ->
          pr "  char **%s;\n" n
        | Bool n -> pr "  int %s;\n" n
        | Int n -> pr "  int %s;\n" n
        | Int64 n -> pr "  int64_t %s;\n" n
        | Pointer (t, n) -> pr "  void * /* %s */ %s;\n" t n
      ) args;
      if optargs <> [] then (
        pr "  struct %s optargs_s = { .bitmask = 0 };\n" c_function;
        pr "  struct %s *optargs = &optargs_s;\n" c_function
      );
      pr "\n";

      pr "  if (g == NULL)\n";
      pr "    return luaL_error (L, \"Guestfs.%%s: handle is closed\",\n";
      pr "                       \"%s\");\n" name;
      pr "\n";

      List.iteri (
        fun i ->
          let i = i+2 in (* Lua indexes from 1(!), plus the handle. *)
          function
          | String (_, n) ->
            pr "  %s = luaL_checkstring (L, %d);\n" n i
          | BufferIn n ->
            pr "  %s = luaL_checklstring (L, %d, &%s_size);\n" n i n
          | OptString n ->
            pr "  %s = luaL_optstring (L, %d, NULL);\n" n i
          | StringList (_, n) ->
            pr "  %s = get_string_list (L, %d);\n" n i
          | Bool n ->
            pr "  %s = lua_toboolean (L, %d);\n" n i
          | Int n ->
            pr "  %s = luaL_checkint (L, %d);\n" n i
          | Int64 n ->
            pr "  %s = get_int64 (L, %d);\n" n i
          | Pointer (t, n) ->
            pr "  %s = POINTER_NOT_IMPLEMENTED (\"%s\");\n" n t
      ) args;

      if optargs <> [] then (
        (* Index of the optarg table on the stack. *)
        let optarg_index = List.length args + 2 in

        pr "\n";
        pr "  /* Check for optional arguments, encoded in a table. */\n";
        pr "  if (lua_type (L, %d) == LUA_TTABLE) {\n" optarg_index;

        List.iter (
          fun optarg ->
            let n = name_of_optargt optarg in
            let uc_n = String.uppercase_ascii n in
            pr "    OPTARG_IF_SET (%d, \"%s\",\n" optarg_index n;
            pr "      optargs_s.bitmask |= %s_%s_BITMASK;\n"
              c_optarg_prefix uc_n;
            (match optarg with
            | OBool n ->
              pr "      optargs_s.%s = lua_toboolean (L, -1);\n" n
            | OInt n ->
              pr "      optargs_s.%s = luaL_checkint (L, -1);\n" n
            | OInt64 n ->
              pr "      optargs_s.%s = get_int64 (L, -1);\n" n
            | OString n ->
              pr "      optargs_s.%s = luaL_checkstring (L, -1);\n" n
            | OStringList n ->
              pr "      optargs_s.%s = get_string_list (L, -1);\n" n
            );
            pr "    );\n"
        ) optargs;

        pr "  }\n";
      );
      pr "\n";

      (* Invoke the C function. *)
      pr "  r = %s " c_function;
      generate_c_call_args ~handle:"g" style;
      pr ";\n";

      (* Free temporary data. *)
      List.iter (
        function
        | String _ | BufferIn _ | OptString _
        | Bool _ | Int _ | Int64 _
        | Pointer _ -> ()
        | StringList (_, n) ->
          pr "  free (%s);\n" n
      ) args;
      List.iter (
        function
        | OBool _ | OInt _ | OInt64 _ | OString _ -> ()
        | OStringList n ->
          pr "  free ((char *) optargs_s.%s);\n" n
      ) optargs;

      (* Handle errors. *)
      (match errcode_of_ret ret with
      | `CannotReturnError -> ()
      | `ErrorIsMinusOne ->
        pr "  if (r == -1)\n";
        pr "    return last_error (L, g);\n";
        pr "\n"
      | `ErrorIsNULL ->
        pr "  if (r == NULL)\n";
        pr "    return last_error (L, g);\n";
        pr "\n"
      );

      (* Push return value on the stack. *)
      (match ret with
      | RErr -> ()
      | RInt _ ->
        pr "  lua_pushinteger (L, r);\n"
      | RBool _ ->
        pr "  lua_pushboolean (L, r);\n"
      | RInt64 _ ->
        pr "  push_int64 (L, r);\n"
      | RConstString _
      | RConstOptString _ ->
        pr "  lua_pushstring (L, r);\n"
      | RString _ ->
        pr "  lua_pushstring (L, r);\n";
        pr "  free (r);\n"
      | RStringList _ ->
        pr "  push_string_list (L, r);\n";
        pr "  guestfs_int_free_string_list (r);\n"
      | RHashtable _ ->
        pr "  push_table (L, r);\n";
        pr "  guestfs_int_free_string_list (r);\n"
      | RStruct (_, typ) ->
        pr "  push_%s (L, r);\n" typ;
        pr "  guestfs_free_%s (r);\n" typ
      | RStructList (_, typ) ->
        pr "  push_%s_list (L, r);\n" typ;
        pr "  guestfs_free_%s_list (r);\n" typ
      | RBufferOut _ ->
        pr "  lua_pushlstring (L, r, size);\n";
        pr "  free (r);\n"
      );

      if ret = RErr then
        pr "  return 0;\n"
      else
        pr "  return 1;\n";
      pr "}\n";
      pr "\n"
  ) (actions |> external_functions |> sort);

  pr "\
static struct userdata *
get_handle (lua_State *L, int index)
{
  struct userdata *u;

  u = luaL_checkudata (L, index, GUESTFS_LUA_HANDLE);
  return u;
}

/* NB: caller must free the array, but NOT the strings */
static char **
get_string_list (lua_State *L, int index)
{
  const size_t len = lua_objlen (L, index);
  size_t i;
  char **strs;
  char err[256];

  strs = malloc ((len+1) * sizeof (char *));
  if (strs == NULL) {
    luaL_error (L, \"get_string_list: malloc failed: %%s\",
                guestfs_int_strerror (errno, err, sizeof err));
    /*NOTREACHED*/
    return NULL;
  }

  for (i = 0; i < len; ++i) {
    lua_rawgeti (L, index, i+1 /* because of base 1 arrays */);
    strs[i] = (char *) luaL_checkstring (L, -1);
    lua_pop (L, 1);
  }
  strs[len] = NULL;

  return strs;
}

static void
push_string_list (lua_State *L, char **strs)
{
  size_t i;

  lua_newtable (L);
  for (i = 0; strs[i] != NULL; ++i) {
    lua_pushstring (L, strs[i]);
    lua_rawseti (L, -2, i+1 /* because of base 1 arrays */);
  }
}

static void
push_table (lua_State *L, char **table)
{
  size_t i;

  lua_newtable (L);
  for (i = 0; table[i] != NULL; i += 2) {
    lua_pushstring (L, table[i]);
    lua_pushstring (L, table[i+1]);
    lua_settable (L, -3);
  }
}

/* Because Lua doesn't have real 64 bit ints (eg. on 32 bit), which
 * sucks, we implement these as strings.  It's left as an exercise to
 * the caller to turn strings to/from integers.
 */
static int64_t
get_int64 (lua_State *L, int index)
{
  int64_t r;
  const char *s;

  switch (lua_type (L, index)) {
  case LUA_TSTRING:
    s = luaL_checkstring (L, index);
    if (sscanf (s, \"%%\" SCNi64, &r) != 1)
      return luaL_error (L, \"int64 parameter expected\");
    return r;

  case LUA_TNUMBER:
    return luaL_checkint (L, index);

  default:
    return luaL_error (L, \"expecting 64 bit integer\");
  }
}

static void
push_int64 (lua_State *L, int64_t i64)
{
  char s[64];

  snprintf (s, sizeof s, \"%%\" PRIi64, i64);
  lua_pushstring (L, s);
}

static void
push_int64_array (lua_State *L, const int64_t *array, size_t len)
{
  size_t i;

  lua_newtable (L);
  for (i = 0; i < len; ++i) {
    push_int64 (L, array[i]);
    lua_rawseti (L, -2, i+1 /* because of base 1 arrays */);
  }
}

/* Use Lua tostring method to print out any.  Useful for debugging
 * these bindings, but also used if a callback throws an exception.
 */
static void
print_any (lua_State *L, int index, FILE *out)
{
  lua_getglobal(L, \"tostring\");
  lua_pushvalue (L, index >= 0 ? index : index-1);
  lua_call (L, 1, 1);
  fprintf (out, \"%%s\", luaL_checkstring (L, -1));
  lua_pop (L, 1);
}

";

  (* Code to handle events. *)
  pr "\
static const char *event_all[] = {
";

  List.iter (
    fun (event, _) -> pr "  \"%s\",\n" event
  ) events;

  pr "  NULL
};

static uint64_t
get_event_bitmask (lua_State *L, int index)
{
  uint64_t bitmask;

  if (lua_isstring (L, index))
    return get_event (L, index);

  bitmask = 0;

  lua_pushnil (L);
  while (lua_next (L, index) != 0) {
    bitmask |= get_event (L, -1);
    lua_pop (L, 1); /* pop value */
  }
  lua_pop (L, 1); /* pop key */

  return bitmask;
}

static uint64_t
get_event (lua_State *L, int index)
{
  const int r = luaL_checkoption (L, index, NULL, event_all);
  return UINT64_C(1) << r;
}

static void
push_event (lua_State *L, uint64_t event)
{
";

  List.iter (
    fun (event, i) ->
      pr "  if (event == %d) {\n" i;
      pr "    lua_pushliteral (L, \"%s\");\n" event;
      pr "    return;\n";
      pr "  }\n";
  ) events;

  pr "  abort (); /* should never happen */
}

";

  (* Code to push structs. *)
  let generate_push_struct typ =
    pr "static void\n";
    pr "push_%s (lua_State *L, struct guestfs_%s *v)\n" typ typ;
    pr "{\n";
    pr "  lua_newtable (L);\n";
    List.iter (
      fun (n, field) ->
        pr "  lua_pushliteral (L, \"%s\");\n" n;
        (match field with
        | FChar ->
          pr "  lua_pushlstring (L, &v->%s, 1);\n" n
        | FString ->
          pr "  lua_pushstring (L, v->%s);\n" n
        | FBuffer ->
          pr "  lua_pushlstring (L, v->%s, v->%s_len);\n" n n
        | FUInt32
        | FInt32 ->
          pr "  lua_pushinteger (L, v->%s);\n" n
        | FUInt64
        | FInt64
        | FBytes ->
          pr "  push_int64 (L, (int64_t) v->%s);\n" n
        | FUUID ->
          pr "  lua_pushlstring (L, v->%s, 32);\n" n
        | FOptPercent ->
          pr "  lua_pushnumber (L, v->%s);\n" n
        );
        pr "  lua_settable (L, -3);\n"
    ) (lookup_struct typ).s_cols;
    pr "}\n";
    pr "\n";

  and generate_push_struct_list typ =
    pr "static void\n";
    pr "push_%s_list (lua_State *L, struct guestfs_%s_list *v)\n" typ typ;
    pr "{\n";
    pr "  size_t i;\n";
    pr "\n";
    pr "  lua_newtable (L);\n";
    pr "  for (i = 0; i < v->len; ++i) {\n";
    pr "    push_%s (L, &v->val[i]);\n" typ;
    pr "    lua_rawseti (L, -2, i+1 /* because of base 1 arrays */);\n";
    pr "  }\n";
    pr "}\n";
    pr "\n"
  in

  List.iter (
    function
    | typ, RStructOnly ->
      generate_push_struct typ
    | typ, (RStructListOnly | RStructAndList) ->
      generate_push_struct typ;
      generate_push_struct_list typ
  ) (rstructs_used_by (actions |> external_functions));

  pr "\
/* Metamethods.
 * See: http://article.gmane.org/gmane.comp.lang.lua.general/95065
 */
static luaL_Reg metamethods[] = {
  { \"__gc\", guestfs_int_lua_finalizer },
  { NULL, NULL }
};

/* Module functions. */
static luaL_Reg functions[] = {
  { \"create\", guestfs_int_lua_create },
  { NULL, NULL }
};

/* Methods. */
static luaL_Reg methods[] = {
  { \"close\", guestfs_int_lua_close },
  { \"set_event_callback\", guestfs_int_lua_set_event_callback },
  { \"delete_event_callback\", guestfs_int_lua_delete_event_callback },

";

  List.iter (
    fun { name } -> pr "  { \"%s\", guestfs_int_lua_%s },\n" name name
  ) (actions |> external_functions |> sort);

  pr "\

  { NULL, NULL }
};

static void
make_version_string (char *version, size_t size)
{
  guestfs_h *g;
  struct guestfs_version *v;

  g = guestfs_create ();
  v = guestfs_version (g);
  snprintf (version, size,
            \"libguestfs %%\" PRIi64 \".%%\" PRIi64 \".%%\" PRIi64 \"%%s\",
            v->major, v->minor, v->release, v->extra);
  free (v);
  guestfs_close (g);
}

extern int luaopen_guestfs (lua_State *L);

int
luaopen_guestfs (lua_State *L)
{
  char v[256];

  /* Create metatable. */
  luaL_newmetatable (L, GUESTFS_LUA_HANDLE);
#if LUA_VERSION_NUM >= 502
  luaL_setfuncs (L, metamethods, 0);
#else
  luaL_register (L, NULL, metamethods);
#endif

  /* Create methods table. */
  lua_newtable (L);
#if LUA_VERSION_NUM >= 502
  luaL_setfuncs (L, methods, 0);
#else
  luaL_register (L, NULL, methods);
#endif

  /* Set __index field of metatable to point to methods table. */
  lua_setfield (L, -2, \"__index\");

  /* Pop metatable, it is no longer needed. */
  lua_pop (L, 1);

  /* Create module functions table. */
  lua_newtable (L);
#if LUA_VERSION_NUM >= 502
  luaL_setfuncs (L, functions, 0);
#else
  luaL_register (L, NULL, functions);
#endif

  /* Globals in the module namespace. */
  lua_pushliteral (L, \"event_all\");
  push_string_list (L, (char **) event_all);
  lua_settable (L, -3);

  /* Add _COPYRIGHT, etc. fields to the module namespace. */
  lua_pushliteral (L, \"_COPYRIGHT\");
  lua_pushliteral (L, \"Copyright (C) %s Red Hat Inc.\");
  lua_settable (L, -3);

  lua_pushliteral (L, \"_DESCRIPTION\");
  lua_pushliteral (L, \"Lua binding to libguestfs\");
  lua_settable (L, -3);

  lua_pushliteral (L, \"_VERSION\");
  make_version_string (v, sizeof v);
  lua_pushlstring (L, v, strlen (v));
  lua_settable (L, -3);

  /* Return module table, so users choose their own name for the module:
   * local G = require \"guestfs\"
   * g = G.create ()
   */
  return 1;
}
" copyright_years;
