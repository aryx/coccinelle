(*
 * This file is part of Coccinelle, licensed under the terms of the GPL v2.
 * See copyright.txt in the Coccinelle source code for more information.
 * The Coccinelle source code can be obtained at https://coccinelle.gitlabpages.inria.fr/website
 *)

val process : Ast0_cocci.rule -> Ast0_cocci.rule

val process_anything : Ast0_cocci.anything -> Ast0_cocci.anything
