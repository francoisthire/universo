module L = Common.Log
module P = Parser.Parse_channel
module F = Common.Files
module O = Common.Oracle
module U = Common.Universes
module Syn = Solving.Solver.Z3Syn
module Arith = Solving.Solver.Z3Arith
module ZSyn = Solving.Z3cfg.Make(Syn)
module ZArith = Solving.Z3cfg.Make(Arith)
module S = Solving.Solver.Make(ZArith)

let _ =
  (* For debugging purposes, it is better to see error messages in SNF *)
  Errors.errors_in_snf := true;
  (* Dedukti option to avoid problems with signatures and rewriting on static symbols. *)
  Signature.unsafe := true

(** Direct the control flow of Universo. The control flow of Universo can be sum up in 4 steps:
    1) Elaborate the files to replace universes by variables
    2) Check the files to generate constraints
    3) Solve the constraints
    4) Reconstruct the files with the solution *)
type execution_mode =
  | Normal (** Go through the four steps above *)
  | JustElaborate (** Do not generate constraints (only step 1). *)
  | JustCheck (** Only generate constraints (only step 2). ASSUME that elaboration has been done before. *)
  | JustSolve (** Only solve the constraints (only step 3). ASSUME that constraints has been generated before. *)

(** By default, Universo go through all the steps *)
let mode = Pervasives.ref Normal

let add_requires fmt mds = List.iter (fun md -> Format.fprintf fmt "#REQUIRE %a.@." Pp.print_mident md)  mds

(** [elaborate file] generates two new files [file'] and [file_univ].
    [file'] is the same as [file] except that all universes are replaced by fresh variables.
    [file_univ] contains the declaration of these variables. Everything is done modulo the logic. *)
let elaborate : string  -> unit = fun in_path ->
  let in_file = F.in_from_string in_path `Input in
  let env = Cmd.to_elaboration_env in_file.path in
  let entries = P.parse in_file.md (F.in_channel_of_file in_file) in
  (* This steps generates the fresh universe variables *)
  let entries' = List.map (Elaboration.Elaborate.mk_entry env) entries in
  (* Write the elaborated terms in the normal file (in the output directory) *)
  let out_file = F.out_from_string in_path `Output in
  let out_fmt = F.fmt_of_file out_file in
  (* The elaborated file depends on the out_sol_md file that contains solution. If the mode is JustElaborate, then this file is empty and import the declaration of the fresh universes *)
  add_requires out_fmt [F.md_of in_path `Elaboration; F.md_of in_path `Solution];
  List.iter (Pp.print_entry out_fmt) entries';
  F.close_in in_file;
  F.close_out out_file

(** [check file] type checks the file [file] and write the generated constraints in the file [file_cstr]. ASSUME that [file_univ] has been generated previously.
    ASSUME also that the dependencies have been type checked before. *)
let check : string -> unit = fun in_path ->
  let md = F.md_of_path in_path in
  let out_file = F.get_out_path in_path `Output in
  let ic = open_in out_file in
  let entries = P.parse md ic in
  let env = Cmd.to_checking_env in_path in
  let meta = Dkmeta.meta_of_file false !Cmd.compat_theory in
  let entries' = List.map (Dkmeta.mk_entry meta md) entries in
  List.iter (Checking.Checker.mk_entry env) entries';
  L.log_check "[CHECK] Printing constraints...";
  Common.Constraints.flush {Common.Constraints.out_fmt=env.check_fmt; meta=env.meta_out}

(** [solve files] call a SMT solver on the constraints generated for all the files [files].
    ASSUME that [file_cstr] and [file_univ] have been generated for all [file] in [files]. *)
let solve : string list -> unit = fun in_paths ->
  let add_constraints in_path =
    let file_cstr = F.get_out_path in_path `Checking in
    let meta = Dkmeta.meta_of_file false !Cmd.compat_theory in
    S.parse meta file_cstr
  in
  List.iter add_constraints in_paths;
  L.log_univ "[SOLVING CONSTRAINTS...]";
  let mk_theory i = O.mk_theory (Cmd.theory_meta ()) i in
  let i,model = S.solve mk_theory in
  L.log_univ "[SOLVED] Solution found with %d universes." i;
  let meta_out = Dkmeta.meta_of_file false !Cmd.compat_output in
  List.iter (S.print_model meta_out model) in_paths

(** [run_on_file file] process steps 1 and 2 (depending the mode selected on [file] *)
let run_on_file file =
  L.log_univ "[FILE] %s" file;
  match !mode with
  | Normal ->
    elaborate file;
    check file
  | JustElaborate ->
    elaborate file
  | JustCheck ->
    check file
  | JustSolve -> ()

let cmd_options =
  [ ( "-d"
    , Arg.String L.enable_flag
    , " flags enables debugging for all given flags" )
  ; ( "--elab-only"
    , Arg.Unit (fun _ -> mode := JustElaborate)
    , " only elaborate files" )
  ; ( "--check-only"
    , Arg.Unit (fun _ -> mode := JustCheck)
    , " only generate constraints" )
  ; ( "--solve-only"
    , Arg.Unit (fun _ -> mode := JustSolve)
    , " only solves the constraints" )
  ; ( "-I"
    , Arg.String Basic.add_path
    , " DIR Add the directory DIR to the load path" )
  ; ( "-o"
    , Arg.String (fun s -> F.output_directory := Some s; Basic.add_path s)
    , " Set the output directory" )
  ; ( "--theory"
    , Arg.String (fun s -> Cmd.theory := s)
    , " Theory file" )
  ; ( "--to-theory"
    , Arg.String (fun s -> Cmd.compat_theory := s)
    , " Rewrite rules mapping input theory universes' to Universo's universes" )
  ; ( "--to-elaboration"
    , Arg.String (fun s -> Cmd.compat_input := s)
    , " Rewrite rules mapping theory's universes to be replaced to Universo's variables" )
  ; ( "--of-universo"
    , Arg.String  (fun s -> Cmd.compat_output := s)
    , " Rewrite rules mapping Universo's universes to the theory's universes" )]

(** [generate_empty_sol_file file] generates the file [file_sol] that requires the file [file_univ].
    This is necessary when universo is used with another mode than the Normal one (see elaboration). *)
let generate_empty_sol_file : string -> unit = fun in_path ->
  let sol_file = F.get_out_path in_path `Solution in
  let check_md = F.md_of_path (F.get_out_path in_path `Checking) in
  let oc = open_out sol_file in
  let fmt = Format.formatter_of_out_channel oc in
  Format.fprintf fmt "#REQUIRE %a.@.@." Pp.print_mident check_md;
  close_out oc

let _ =
  try
    let options = Arg.align cmd_options in
    let usage = "Usage: " ^ Sys.argv.(0) ^ " [OPTION]... [FILE]... \n" in
    let usage = usage ^ "Available options:" in
    let files =
      let files = ref [] in
      Arg.parse options (fun f -> files := f :: !files) usage;
      List.rev !files
    in
    List.iter run_on_file files;
    List.iter generate_empty_sol_file files;
    if !mode = Normal || !mode = JustSolve then
      solve files;
  with
  | Env.EnvError(l,e) -> Errors.fail_env_error l e
  | Signature.SignatureError e ->
     Errors.fail_env_error Basic.dloc (Env.EnvErrorSignature e)
  | Typing.TypingError e ->
    Errors.fail_env_error Basic.dloc (Env.EnvErrorType e)
  | Sys_error err -> Printf.eprintf "ERROR %s.\n" err; exit 1
  | Exit          -> exit 3
