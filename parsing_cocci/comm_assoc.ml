(*
 * This file is part of Coccinelle, licensed under the terms of the GPL v2.
 * See copyright.txt in the Coccinelle source code for more information.
 * The Coccinelle source code can be obtained at https://coccinelle.gitlabpages.inria.fr/website
 *)

(* searches for E op ..., for any commutative and associative binary
operator.  When this satisfies the isomorphism conditions (ie all minus, or
context for the op and ...), then this is converted to Nested(E,op).
Nested is not used before this phase. *)

module Ast = Ast_cocci
module Ast0 = Ast0_cocci
module V0 = Visitor_ast0
module VT0 = Visitor_ast0_types
module U = Unparse_ast0

let comm_assoc_arith = function
    Ast.Plus | Ast.Mul | Ast.And _ | Ast.Or _ -> true
  | _ -> false

let comm_assoc_logical = function
    Ast.AndLog _ | Ast.OrLog _ -> true
  | _ -> false

let is_comm_assoc op0 = match Ast0.unwrap op0 with
  | Ast0.Arith op -> comm_assoc_arith (Ast0.unwrap_mcode op)
  | Ast0.Logical op -> comm_assoc_logical (Ast0.unwrap_mcode op)
  | Ast0.MetaBinary _ -> false

let is_minus e =
  match Ast0.get_mcodekind e with Ast0.MINUS(cell) -> true | _ -> false

let is_context e =
  !Flag.sgrep_mode2 || (* everything is context for sgrep *)
  (match Ast0.get_mcodekind e with
    Ast0.CONTEXT(cell) -> true
  | _ -> false)

let nopos mc = (Ast0.get_pos mc) = []

let nopos_op op0 = match Ast0.unwrap op0 with
  | Ast0.Arith op -> nopos op
  | Ast0.Logical op -> nopos op
  | Ast0.MetaBinary(mv,_,_) -> nopos mv

let process_binops rule_name =
  let expr r k e1 =
    let e = k e1 in
    match Ast0.unwrap e with
      Ast0.Binary(left,op,right)
      when is_comm_assoc op ->
	(match Ast0.unwrap right with
	  Ast0.Edots(d,None) ->
	    if (is_minus e || (is_context op && is_context right))
		&& nopos_op op && nopos d
	    (* keep dots to record required modif *)
	    then Ast0.rewrap e (Ast0.Nested(left,op,right))
	    else
	      (Common.pr2
		 (Printf.sprintf
		    "%s: position variables or mixed modifs interfere with comm_assoc iso\n%s"
		    rule_name
		    (U.unparse_x_to_string U.expression e1));
	       e)
	| Ast0.Edots(d,_) ->
	    (Common.pr2
	       (Printf.sprintf
		  "%s: whencode interferes with comm_assoc iso\n%s" rule_name
		  (U.unparse_x_to_string U.expression e1));
	     e)
	| _ -> e)
    | _ -> e in
  V0.rebuilder_default ~expr:expr ()

let comm_assoc rule rule_name dropped_isos =
  if List.mem "comm_assoc" dropped_isos
  then rule
  else List.map (process_binops rule_name).VT0.rebuilder_rec_top_level rule
