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


type cocci_predicate = Lib_engine.predicate * Ast_cocci.meta_name Ast_ctl.modif
type formula =
    (cocci_predicate,Ast_cocci.meta_name, Wrapper_ctl.info) Ast_ctl.generic_ctl

let poplz (name,_,ast) =
  match ast with
    [ast] ->
      let ast = Asttopopl.top ast in
      let ba = Insert_befaft.insert_befaft ast in
      let qt = Insert_quantifiers.insert_quantifiers ba in
      [Popltoctl.toctl qt]
  | _ -> failwith "only one rule allowed"

let popl r =
  match r with
    Ast_cocci.CocciRule (a,b,c) -> poplz (a,b,c)
  | _ -> []
