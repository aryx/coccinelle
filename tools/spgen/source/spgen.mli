(*
 * This file is part of Coccinelle, licensed under the terms of the GPL v2.
 * See copyright.txt in the Coccinelle source code for more information.
 * The Coccinelle source code can be obtained at https://coccinelle.gitlabpages.inria.fr/website
 *)

(* Driver module for spgen.
 *
 * Options:
 *  - config: the name of the file to draw user input from
 *  - output: the name of the file to save the generated file (default: stdout)
 *  - interactive: if true, draw user input interactively
 *  - default: if true, generate without user input (using default values)
 *  - hide: if true, do not output the generated file
 *  - year: current year (for copyright in generated header)
 *)

type options

val make_options :
  ?config:string ->
  ?output:string ->
  ?interactive:bool ->
  ?default:bool ->
  ?hide:bool ->
  ?year:int ->
  string -> (* filename of cocci file to generate *)
  options

val run : options -> unit
