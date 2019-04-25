module B = Basic
module U = Common.Universes
module Z = Z3cfg
module ZA = Z.Arithmetic
module ZB = Z.Boolean
module ZI = ZA.Integer

type t = Z.Expr.expr

let mk_name : B.name -> string = fun name ->
  B.string_of_mident (B.md name) ^ (B.string_of_ident (B.id name))

let int_sort = ZI.mk_sort Z.ctx

let mk_var  : string -> t = fun s ->
  Z.Expr.mk_const_s Z.ctx s int_sort

let to_int : int -> t = fun i -> ZI.mk_numeral_i Z.ctx i

let mk_prop : t = to_int 0

let mk_set : t = to_int 1

let mk_type : int -> t = fun i -> to_int (i+1)

let mk_univ : U.univ -> t = fun _ -> failwith "todo mk_univ z3arith"

let mk_axiom : t -> t -> t = fun l r ->
  ZB.mk_ite Z.ctx (ZB.mk_eq Z.ctx l mk_prop)
    (ZB.mk_eq Z.ctx (ZA.mk_add Z.ctx [l;(to_int 1)]) r)
    (ZB.mk_eq Z.ctx (ZA.mk_add Z.ctx [l;(to_int 1)]) r)

let mk_cumul : t -> t -> t = fun l r -> ZA.mk_le Z.ctx l r

let mk_max : t -> t -> t = fun l r ->
  ZB.mk_ite Z.ctx (ZA.mk_le Z.ctx l r) r l

let mk_rule : t -> t -> t -> t = fun x y z ->
  ZB.mk_ite Z.ctx (ZB.mk_eq Z.ctx y mk_prop)
    (ZB.mk_eq Z.ctx z mk_prop)
    (ZB.mk_eq Z.ctx z (mk_max x y))
(*    (ZB.mk_ite Z.ctx (ZB.mk_eq Z.ctx x mk_prop)
       (ZB.mk_and Z.ctx [ZB.mk_eq Z.ctx y mk_prop; ZB.mk_eq Z.ctx z mk_prop])
       (ZB.mk_eq Z.ctx z (mk_max x y))) *)

let mk_bounds : string -> int -> t = fun _ _ ->
  failwith "mk_bounds (z3arith)"
(*
  let var = mk_var var in
  if predicative then
    ZB.mk_and Z.ctx [ZA.mk_le Z.ctx (to_int 1) var; ZA.mk_lt Z.ctx var (to_int i)]
  else
    ZB.mk_and Z.ctx [ZA.mk_le Z.ctx (to_int 0) var; ZA.mk_lt Z.ctx var (to_int i)] *)

let solution_of_var : int -> Z.Model.model -> string -> U.univ option = fun _ model var ->
  match Z.Model.get_const_interp_e model (mk_var var) with
  | None -> assert false
  | Some e ->
    let _ = Big_int.int_of_big_int (ZI.get_big_int e) in
    failwith "solution_of_var (z3 arith)"
