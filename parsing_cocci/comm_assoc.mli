(*
 * This file is part of Coccinelle, licensed under the terms of the GPL v2.
 * See copyright.txt in the Coccinelle source code for more information.
 * The Coccinelle source code can be obtained at https://coccinelle.gitlabpages.inria.fr/website
 *)

val comm_assoc :
    Ast0_cocci.rule -> string (* rule name *) ->
      string list (* dropped isos *) -> Ast0_cocci.rule
