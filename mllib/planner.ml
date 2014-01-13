(* virt-builder
 * Copyright (C) 2012-2014 Red Hat Inc.
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
 *)

type ('name, 'value) tag = 'name * 'value

type ('name, 'value) tags = ('name, 'value) tag list

type ('name, 'value, 'task) plan =
  (('name, 'value) tags * 'task * ('name, 'value) tags) list

type ('name, 'value, 'task) transitions_function =
  ('name, 'value) tags -> ('task * int * ('name, 'value) tags) list

let plan ?(max_depth = 10) transitions itags (goal_must, goal_must_not) =
  (* Do the given output tags match the finish condition? *)
  let finished (otags, _, _) =
    let must =
      (* All tags from the MUST list must be present with the given values. *)
      List.for_all (
        fun (name, value) ->
          try List.assoc name otags = value with Not_found -> false
      ) goal_must in

    let must_not =
      (* No tag from the MUST NOT list can appear. *)
      List.for_all (
        fun (name, value) ->
          try List.assoc name otags <> value with Not_found -> true
      ) goal_must_not in

    must && must_not
  in

  (* Breadth-first search. *)
  let rec search depth paths =
    if depth >= max_depth then failwith "plan"
    else (
      let paths =
        List.map (
          fun (itags, weight, preds) ->
            let ts = transitions itags in
            List.map (fun (task, w, otags) ->
              otags, weight + w, (itags, task, otags) :: preds
            ) ts
        ) paths in
      let paths = List.flatten paths in

      (* Did any path reach the finish?  If so, pick the path with the
       * smallest weight and we're done.
       *)
      let finished_paths = List.filter finished paths in
      let finished_paths =
        List.sort (fun (_,w1,_) (_,w2,_) -> compare w1 w2) finished_paths in
      match finished_paths with
      | [] ->
        (* No path reached the finish, so go deeper. *)
        search (depth+1) paths
      | (_, _, ret) :: _ ->
        (* Return the shortest path, but we have to reverse it because
         * we built it backwards.
         *)
        List.rev ret
    )
  in

  search 0 [itags, 0, []]
