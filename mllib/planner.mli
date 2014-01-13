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

(** The Planner can plan how to reach a goal by carrying out a series
    of operations.  You tag the input state and the output state, and
    give it a list of permitted transitions, and it will return a
    multi-step plan (list of transitions) from the input state to the
    output state.

    For an explanation of the Planner, see:
    http://rwmj.wordpress.com/2013/12/14/writing-a-planner-to-solve-a-tricky-programming-optimization-problem/

    Tags are described as OCaml association lists.  See the OCaml
    {!List} module.

    Transitions are defined by a function (that the caller supplies)
    which returns the possible transitions for a given set of tags,
    and for each possible transition, the weight (higher number =
    higher cost), and the tag state after that transition.

    The returned plan is a list of transitions.

    The implementation is a simple breadth-first search of the tree of
    states (each edge in the tree is a transition).  It doesn't work
    very hard to optimize the weights, so the returned plan is
    possible, but might not be optimal. *)

type ('name, 'value) tag = 'name * 'value

type ('name, 'value) tags = ('name, 'value) tag list
  (** An assoc-list of tags. *)

type ('name, 'value, 'task) plan =
  (('name, 'value) tags * 'task * ('name, 'value) tags) list

type ('name, 'value, 'task) transitions_function =
  ('name, 'value) tags -> ('task * int * ('name, 'value) tags) list

val plan : ?max_depth:int -> ('name, 'value, 'task) transitions_function -> ('name, 'value) tags -> ('name, 'value) tags * ('name, 'value) tags -> ('name, 'value, 'task) plan
(** Make a plan.

    [plan transitions itags (goal_must, goal_must_not)] works out a
    plan, which is a list of tasks that have to be carried out in
    order to go from the input tags to the goal.  The goal is passed
    in as a pair of lists: tags that MUST appear and tags that MUST
    NOT appear.

    The returned value is a {!plan}.

    Raises [Failure "plan"] if no plan was found within [max_depth]
    transitions. *)
