(*
* Copyright 2005-2008, Ecole des Mines de Nantes, University of Copenhagen
* Yoann Padioleau, Julia Lawall, Rene Rydhof Hansen, Henrik Stuart, Gilles Muller
* This file is part of Coccinelle.
* 
* Coccinelle is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, according to version 2 of the License.
* 
* Coccinelle is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
* 
* You should have received a copy of the GNU General Public License
* along with Coccinelle.  If not, see <http://www.gnu.org/licenses/>.
* 
* The authors reserve the right to distribute this or future versions of
* Coccinelle under other licenses.
*)


(* find unitary metavariables *)
module Ast0 = Ast0_cocci
module Ast = Ast_cocci
module V0 = Visitor_ast0

let set_minus s minus = List.filter (function n -> not (List.mem n minus)) s

let rec nub = function
    [] -> []
  | (x::xs) when (List.mem x xs) -> nub xs
  | (x::xs) -> x::(nub xs)

(* ----------------------------------------------------------------------- *)
(* Find the variables that occur free and occur free in a unitary way *)

(* take everything *)
let minus_checker name = let id = Ast0.unwrap_mcode name in [id]

(* take only what is in the plus code *)
let plus_checker (nm,_,_,mc,_) =
  match mc with Ast0.PLUS -> [nm] | _ -> []  
      
let get_free checker t =
  let bind x y = x @ y in
  let option_default = [] in
  let donothing r k e = k e in
  let mcode _ = option_default in
  
  (* considers a single list *)
  let collect_unitary_nonunitary free_usage =
    let free_usage = List.sort compare free_usage in
    let rec loop1 todrop = function
	[] -> []
      | (x::xs) as all -> if x = todrop then loop1 todrop xs else all in
    let rec loop2 = function
	[] -> ([],[])
      | [x] -> ([x],[])
      | x::y::xs ->
	  if x = y
	  then
	    let (unitary,non_unitary) = loop2(loop1 x xs) in
	    (unitary,x::non_unitary)
	  else
	    let (unitary,non_unitary) = loop2 (y::xs) in
	    (x::unitary,non_unitary) in
    loop2 free_usage in
  
  (* considers a list of lists *)
  let detect_unitary_frees l =
    let (unitary,nonunitary) =
      List.split (List.map collect_unitary_nonunitary l) in
    let unitary = nub (List.concat unitary) in
    let nonunitary = nub (List.concat nonunitary) in
    let unitary =
      List.filter (function x -> not (List.mem x nonunitary)) unitary in
    unitary@nonunitary@nonunitary in

  let whencode afn bfn expression = function
      Ast0.WhenNot(a) -> afn a
    | Ast0.WhenAlways(b) -> bfn b
    | Ast0.WhenModifier(_) -> option_default
    | Ast0.WhenNotTrue(a) -> expression a
    | Ast0.WhenNotFalse(a) -> expression a in
  
  let ident r k i =
    match Ast0.unwrap i with
      Ast0.MetaId(name,_,_) | Ast0.MetaFunc(name,_,_)
    | Ast0.MetaLocalFunc(name,_,_) -> checker name
    | _ -> k i in
  
  let expression r k e =
    match Ast0.unwrap e with
      Ast0.MetaErr(name,_,_) | Ast0.MetaExpr(name,_,_,_,_)
    | Ast0.MetaExprList(name,_,_) -> checker name
    | Ast0.DisjExpr(starter,expr_list,mids,ender) ->
	detect_unitary_frees(List.map r.V0.combiner_expression expr_list)
    | _ -> k e in
  
  let typeC r k t =
    match Ast0.unwrap t with
      Ast0.MetaType(name,_) -> checker name
    | Ast0.DisjType(starter,types,mids,ender) ->
	detect_unitary_frees(List.map r.V0.combiner_typeC types)
    | _ -> k t in
  
  let parameter r k p =
    match Ast0.unwrap p with
      Ast0.MetaParam(name,_) | Ast0.MetaParamList(name,_,_) -> checker name
    | _ -> k p in
  
  let declaration r k d =
    match Ast0.unwrap d with
      Ast0.DisjDecl(starter,decls,mids,ender) ->
	detect_unitary_frees(List.map r.V0.combiner_declaration decls)
    | _ -> k d in

  let statement r k s =
    match Ast0.unwrap s with
      Ast0.MetaStmt(name,_) | Ast0.MetaStmtList(name,_) -> checker name
    | Ast0.Disj(starter,stmt_list,mids,ender) ->
	detect_unitary_frees(List.map r.V0.combiner_statement_dots stmt_list)
    | Ast0.Nest(starter,stmt_dots,ender,whn,multi) ->
	bind (r.V0.combiner_statement_dots stmt_dots)
	  (detect_unitary_frees 
	     (List.map
		(whencode r.V0.combiner_statement_dots r.V0.combiner_statement
		    r.V0.combiner_expression)
		whn))
    | Ast0.Dots(d,whn) | Ast0.Circles(d,whn) | Ast0.Stars(d,whn) ->
	detect_unitary_frees
	  (List.map
	     (whencode r.V0.combiner_statement_dots r.V0.combiner_statement
		r.V0.combiner_expression)
	     whn)
    | _ -> k s in
  
  let res = V0.combiner bind option_default 
      mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode
      mcode
      donothing donothing donothing donothing donothing donothing
      ident expression typeC donothing parameter declaration statement
      donothing donothing in
  
  collect_unitary_nonunitary
    (List.concat (List.map res.V0.combiner_top_level t))
    
(* ----------------------------------------------------------------------- *)
(* update the variables that are unitary *)
    
let update_unitary unitary =
  let donothing r k e = k e in
  let mcode x = x in
  
  let is_unitary name =
    match (List.mem (Ast0.unwrap_mcode name) unitary,
	   !Flag.sgrep_mode2, Ast0.get_mcode_mcodekind name) with
      (true,true,_) | (true,_,Ast0.CONTEXT(_)) -> Ast0.PureContext
    | (true,_,_) -> Ast0.Pure
    | (false,true,_) | (false,_,Ast0.CONTEXT(_)) -> Ast0.Context
    | (false,_,_) -> Ast0.Impure in

  let ident r k i =
    match Ast0.unwrap i with
      Ast0.MetaId(name,constraints,_) ->
	Ast0.rewrap i (Ast0.MetaId(name,constraints,is_unitary name))
    | Ast0.MetaFunc(name,constraints,_) ->
	Ast0.rewrap i (Ast0.MetaFunc(name,constraints,is_unitary name))
    | Ast0.MetaLocalFunc(name,constraints,_) ->
	Ast0.rewrap i (Ast0.MetaLocalFunc(name,constraints,is_unitary name))
    | _ -> k i in

  let expression r k e =
    match Ast0.unwrap e with
      Ast0.MetaErr(name,constraints,_) ->
	Ast0.rewrap e (Ast0.MetaErr(name,constraints,is_unitary name))
    | Ast0.MetaExpr(name,constraints,ty,form,_) ->
	Ast0.rewrap e (Ast0.MetaExpr(name,constraints,ty,form,is_unitary name))
    | Ast0.MetaExprList(name,lenname,_) ->
	Ast0.rewrap e (Ast0.MetaExprList(name,lenname,is_unitary name))
    | _ -> k e in
  
  let typeC r k t =
    match Ast0.unwrap t with
      Ast0.MetaType(name,_) ->
	Ast0.rewrap t (Ast0.MetaType(name,is_unitary name))
    | _ -> k t in
  
  let parameter r k p =
    match Ast0.unwrap p with
      Ast0.MetaParam(name,_) ->
	Ast0.rewrap p (Ast0.MetaParam(name,is_unitary name))
    | Ast0.MetaParamList(name,lenname,_) ->
	Ast0.rewrap p (Ast0.MetaParamList(name,lenname,is_unitary name))
    | _ -> k p in
  
  let statement r k s =
    match Ast0.unwrap s with
      Ast0.MetaStmt(name,_) ->
	Ast0.rewrap s (Ast0.MetaStmt(name,is_unitary name))
    | Ast0.MetaStmtList(name,_) ->
	Ast0.rewrap s (Ast0.MetaStmtList(name,is_unitary name))
    | _ -> k s in
  
  let res = V0.rebuilder
      mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode
      mcode
      donothing donothing donothing donothing donothing donothing
      ident expression typeC donothing parameter donothing statement
      donothing donothing in

  List.map res.V0.rebuilder_top_level

(* ----------------------------------------------------------------------- *)

let rec split3 = function
    [] -> ([],[],[])
  | (a,b,c)::xs -> let (l1,l2,l3) = split3 xs in (a::l1,b::l2,c::l3)

let rec combine3 = function
    ([],[],[]) -> []
  | (a::l1,b::l2,c::l3) -> (a,b,c) :: combine3 (l1,l2,l3)
  | _ -> failwith "not possible"

(* ----------------------------------------------------------------------- *)
(* process all rules *)

let do_unitary rules =
  let rec loop = function
      [] -> ([],[])
    | (r::rules) ->
      match r with
        Ast0.ScriptRule (a,b,c,d) ->
          let (x,rules) = loop rules in
          (x, r::rules)
      | Ast0.CocciRule ((minus,metavars,chosen_isos),((plus,_) as plusz)) ->
          let mm1 = List.map Ast.get_meta_name metavars in
          let (used_after, rest) = loop rules in
          let (m_unitary, m_nonunitary) = get_free minus_checker minus in
          let (p_unitary, p_nonunitary) = get_free plus_checker plus in
          let p_free = 
            if !Flag.sgrep_mode2 then []
            else p_unitary @ p_nonunitary in
          let (in_p, m_unitary) =
            List.partition (function x -> List.mem x p_free) m_unitary in
          let m_nonunitary = in_p @ m_nonunitary in
          let (m_unitary, not_local) =
            List.partition (function x -> List.mem x mm1) m_unitary in
          let m_unitary =
            List.filter (function x -> not (List.mem x used_after))
	      m_unitary in
          let rebuilt = update_unitary m_unitary minus in
          (set_minus (m_nonunitary @ used_after) mm1,
             (Ast0.CocciRule
		((rebuilt, metavars, chosen_isos),plusz))::rest) in
  let (_,rules) = loop rules in
  rules

(*
let do_unitary minus plus =
  let (minus,metavars,chosen_isos) = split3 minus in
  let (plus,_) = List.split plus in
  let rec loop = function
      ([],[],[]) -> ([],[])
    | (mm1::metavars,m1::minus,p1::plus) ->
	let mm1 = List.map Ast.get_meta_name mm1 in
	let (used_after,rest) = loop (metavars,minus,plus) in
	let (m_unitary,m_nonunitary) = get_free minus_checker m1 in
	let (p_unitary,p_nonunitary) = get_free plus_checker p1 in
	let p_free =
	  if !Flag.sgrep_mode2
	  then []
	  else p_unitary @ p_nonunitary in
	let (in_p,m_unitary) =
	  List.partition (function x -> List.mem x p_free) m_unitary in
	let m_nonunitary = in_p@m_nonunitary in
	let (m_unitary,not_local) =
	  List.partition (function x -> List.mem x mm1) m_unitary in
	let m_unitary =
	  List.filter (function x -> not(List.mem x used_after)) m_unitary in
	let rebuilt = update_unitary m_unitary m1 in
	(set_minus (m_nonunitary @ used_after) mm1,
	 rebuilt::rest)
    | _ -> failwith "not possible" in
  let (_,rules) = loop (metavars,minus,plus) in
  combine3 (rules,metavars,chosen_isos)
*)
