open Basic
open Term

module type S =
  sig
    include Typing.Typer

    val mk_entry : Configuration.t -> Entry.entry -> unit
  end

module MakeRE(T:Theory.S) : Reduction.RE =
  struct
    open Reduction
    open Configuration

    let metaify t =
      let open Dkmeta in
      Dkmeta.mk_term T.meta t

    let whnf = Reduction.REDefault.whnf
    let snf = Reduction.REDefault.snf

    let univ_conversion l r =
      if Term.term_eq l r then
        true
      else
        (
          (*          Format.eprintf "l:%a@.r:%a@." Pp.print_term l Pp.print_term r; *)
          true
        )

    let rec are_convertible_lst sg : (term*term) list -> bool = function
      | [] -> true
      | (l,r)::lst ->
         if term_eq l r then are_convertible_lst sg lst
         else
           let l',r' = whnf sg l, whnf sg r in
           (*           Format.eprintf "left:%a@.right:%a@." Pp.print_term l' Pp.print_term r'; *)
           if univ_conversion l' r' then
             are_convertible_lst sg lst
           else
             begin
               (*        Format.eprintf "left:%a@.right:%a@." Pp.print_term l' Pp.print_term r'; *)
               are_convertible_lst sg (Reduction.conversion_step (l',r') lst)
             end

    let are_convertible sg t1 t2 =
      try are_convertible_lst sg [(t1,t2)]
      with NotConvertible -> false
  end

module Make(T:Theory.S) : S =
  struct

    module R = MakeRE(T)

    module T = Typing.Make(R)

    include T

    let mk_entry : Configuration.t -> Entry.entry -> unit = fun cfg e ->
      let open Entry in
      let open Configuration in
      let sg = cfg.sg_check in
      let md = cfg.md_check in
      let _add_rules rs =
        let ris = List.map Rule.to_rule_infos rs in
        Signature.add_rules sg ris
      in
      match e with
      | Decl(lc,id,st,ty) ->
         Format.eprintf "[CHECK] on :%a@." Pp.print_ident id;
         begin
           match inference sg ty with
           | Kind | Type _ -> Signature.add_declaration sg lc id st ty
           | s -> raise (Typing.TypingError (Typing.SortExpected (ty,[],s)))
         end
      | Def(lc,id,opaque,mty,te) ->
        Format.eprintf "[CHECK] on :%a@." Pp.print_ident id;
         let open Rule in
         begin
           let ty = match mty with
             | None -> inference sg te
             | Some ty -> checking sg te ty; ty
           in
           match ty with
           | Kind -> raise (Env.EnvError (lc, Env.KindLevelDefinition id))
           | _ ->
              if opaque then Signature.add_declaration sg lc id Signature.Static ty
              else
                let _ = Signature.add_declaration sg lc id Signature.Definable ty in
                let cst = mk_name md id in
                let rule =
                  { name= Delta(cst) ;
                    ctx = [] ;
                    pat = Pattern(lc, cst, []);
                    rhs = te ;
                  }
                in
                _add_rules [rule]
         end
      | Rules(lc,rs) ->
         let _ = List.map (check_rule sg) rs in
         _add_rules rs
      | _ -> assert false
  end
