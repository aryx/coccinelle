(*
 * This file is part of Coccinelle, licensed under the terms of the GPL v2.
 * See copyright.txt in the Coccinelle source code for more information.
 * The Coccinelle source code can be obtained at https://coccinelle.gitlabpages.inria.fr/website
 *)

(* This tool strips code from a C file that relies on the external
 * macro and type environment, which we would obtain via commandline
 * parameters and includes.
 * The resulting file is more likely to be analyzable without the
 * headers, although it does affect the semantics of the original
 * program.
 *
 * It does so by removing toplevel elements that cannot be parsed
 * correctly because of macro's. Macro's that are interpreted as
 * functions are still kept.
 * It also removes expressions that have an unknown type, and
 * remapping unknown types in types of declarations.
 *)


(* Visitor that hides tokens that cannot be parsed.
 *)
let hide_visitor =
  { Visitor_c.default_visitor_c with
    Visitor_c.ktoplevel = fun (f, self) p ->
      begin
	match p with
	  Ast_c.NotParsedCorrectly ii ->
            let first_i = List.hd ii in
	    let last_i  = List.hd (List.rev ii) in
	    Ast_c.put_annot_info first_i Token_annot.Exclude_start Token_annot.Unit;
	    Ast_c.put_annot_info last_i Token_annot.Exclude_end Token_annot.Unit
	| _ -> ()
      end;
      f p
  }

(* todo: remap visitor *)

(*
    Visitor_c.ktype = fun (f, bigf) ft ->
      let (_, (t, _)) = ft in
      begin match t with
        Ast_c.NoType     -> Common.pr2 "no type"
      | Ast_c.BaseType _ -> Common.pr2 "base type"
      | Ast_c.NamedType (nm, optTp) -> begin
          match optTp with
	    None -> Common.pr2 ("type name " ^ (Ast_c.str_of_name nm) ^ " without fullType")
	  | Some _ -> Common.pr2 ("type name " ^ (Ast_c.str_of_name nm) ^ " with fullType")
          end
      | Ast_c.Pointer _  -> Common.pr2 "pointer"
      | Ast_c.ParenType _ -> Common.pr2 "parens"
      | _                -> Common.pr2 "other"
      end;
      f ft;
    *)

let stripenv source_file dest_file =
  let (ast2,_) = Parse_c.parse_c_and_cpp source_file in
  let ast = Parse_c.program_of_program2 ast2 in
  ignore (Type_annoter_c.annotate_program !Type_annoter_c.initial_env ast);
  ignore (Visitor_c.vk_program hide_visitor ast);
  Unparse_c.pp_program_default ast2 dest_file

let main () =
  Common.print_to_stderr := true;
  Flag_parsing_c.show_parsing_error := true;

  let source = ref None in
  let dest = ref None in
  let path_arg ref path = ref := Some path in
  Arg.parse_argv Sys.argv
    [("--output",Arg.String (path_arg dest),"path to the output file")]
    (path_arg source) "cstripenv <source.c>";
  let source_file =
    match !source with
      None      -> raise (Arg.Bad "a source file argument is required")
    | Some path -> path in
  let dest_file =
    match !dest with
      None      -> raise (Arg.Bad "an output file argument is required")
    | Some path -> path in
  stripenv source_file dest_file

let _ = main ()
