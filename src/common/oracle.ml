module U = Universes

type theory = (U.pred * bool) list
type theory_maker = int -> theory

let rec enumerate : int -> U.univ list = fun i ->
  if i = 0 then
    [U.Enum 0]
  else
    U.Enum i::(enumerate (i-1))

(** [is_true meta p] check if the predicate [p] is true in the original theory. *)
let is_true meta p =
  let t = U.term_of_pred p in
  Format.eprintf "b:%a@." Pp.print_term t;
  let t' = Dkmeta.mk_term meta t in
  Format.eprintf "a:%a@." Pp.print_term t';
  Term.term_eq (U.true_ ()) t'

(** [is_true_axiom meta s s'] check if the predicate [Axiom s s'] is true in the original theory. *)
let is_true_axiom meta s s' =
  let p = U.Axiom(s,s') in
  (p,is_true meta p)

(** [is_true_cumul meta s s'] check if the predicate [Cumul s s'] is true in the original theory. *)
let is_true_cumul meta s s' =
  let p = U.Cumul(s,s') in
  (p, is_true meta p)

(** [is_true_rule meta s s' s''] check if the predicate [Rule s s' s''] is true in the original theory. *)
let is_true_rule meta s s' s'' =
  let p = U.Rule(s,s',s'') in
  (p,is_true meta p)

module Util = struct
  let cartesian2 f l l' =
    List.concat (List.map (fun e -> List.map (fun e' -> f e e') l') l)

  let cartesian3 f l l' l'' =
    List.concat (
      List.map (fun e ->
          List.concat (
            List.map (fun e' ->
                List.map (fun e'' -> f e e' e'') l'') l')) l)
end

(** [mk_theory meta i] computes a theory for the universes up to [i]. A theory is an array for each predicate that tells if the predicate holds. The array is index by universes and its dimension is the arity of the predicate. *)
(* FIXME: can be optimized. *)
let mk_theory : Dkmeta.cfg -> int -> theory = fun meta i ->
  let u  = enumerate i in
  let model_ax  = Util.cartesian2 (fun l r -> is_true_axiom meta l r) u u in
  let model_cu = Util.cartesian2 (fun l r -> is_true_cumul meta l r) u u in
  let model_ru = Util.cartesian3 (fun l m r -> is_true_rule meta l m r) u u u in
  model_ax@model_cu@model_ru
