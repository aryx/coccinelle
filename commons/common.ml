(* Yoann Padioleau
 *
 * Copyright (C) 2010 INRIA, University of Copenhagen DIKU
 * Copyright (C) 1998-2009 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file license.txt.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * license.txt for more details.
 *)

(*****************************************************************************)
(* Notes *)
(*****************************************************************************)



(* ---------------------------------------------------------------------- *)
(* Maybe could split common.ml and use include tricks as in ofullcommon.ml or
 * Jane Street core lib. But then harder to bundle simple scripts like my
 * make_full_linux_kernel.ml because would then need to pass all the files
 * either to ocamlc or either to some #load. Also as the code of many
 * functions depends on other functions from this common, it would
 * be tedious to add those dependencies. Here simpler (have just the
 * pb of the Prelude, but it's a small problem).
 *
 * pixel means code from Pascal Rigaux
 * julia means code from Julia Lawall
 *)
(* ---------------------------------------------------------------------- *)

(*****************************************************************************)
(* We use *)
(*****************************************************************************)
(*
 * modules:
 *   - Stdlib, of course
 *   - List
 *   - Str
 *   - Hashtbl
 *   - Format
 *   - Buffer
 *   - Unix and Sys
 *   - Arg
 *
 * functions:
 *   - =, <=, max min, abs, ...
 *   - List.rev, List.mem, List.partition,
 *   - List.fold*, List.concat, ...
 *   - Str.global_replace
 *   - Filename.is_relative
 *   - String.uppercase, String.lowercase
 *
 *
 * The Format library allows to hide passing an indent_level variable.
 * You use as usual the print_string function except that there is
 * this automatic indent_level variable handled for you (and maybe
 * more services). src: julia in coccinelle unparse_cocci.
 *
 * Extra packages
 *  - ocamlbdb
 *  - ocamlgtk, and gtksourceview
 *  - ocamlgl
 *  - ocamlpython
 *  - ocamlagrep
 *  - ocamlfuse
 *  - ocamlmpi
 *  - ocamlcalendar
 *
 *  - pcre
 *  - sdl
 *
 * Many functions in this file were inspired by Haskell or Lisp libraries.
 *)

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)

(* The following functions should be in their respective sections but
 * because some functions in some sections use functions in other
 * sections, and because I don't want to take care of the order of
 * those sections, of those dependencies, I put the functions causing
 * dependency problem here. C is better than caml on this with the
 * ability to declare prototype, enabling some form of forward
 * reference. *)

let (+>) o f = f o
exception Timeout
exception UnixExit of int

let rec (do_n: int -> (unit -> unit) -> unit) = fun i f ->
  if i = 0 then () else (f(); do_n (i-1) f)
let rec (foldn: ('a -> int -> 'a) -> 'a -> int -> 'a) = fun f acc i ->
  if i = 0 then acc else foldn f (f acc i) (i-1)

let sum_int   = List.fold_left (+) 0

(* could really call it 'for' :) *)
let fold_left_with_index f acc =
  let rec fold_lwi_aux acc n = function
    | [] -> acc
    | x::xs -> fold_lwi_aux (f acc x n) (n+1) xs
  in fold_lwi_aux acc 0


let rec drop n xs =
  match (n,xs) with
  | (0,_) -> xs
  | (_,[]) -> failwith "drop: not enough"
  | (n,x::xs) -> drop (n-1) xs

let rec enum_orig x n = if x = n then [n] else x::enum_orig (x+1)  n

let enum x n =
  if not(x <= n)
  then failwith (Printf.sprintf "bad values in enum, expect %d <= %d" x n);
  let rec enum_aux acc x n =
    if x = n then n::acc else enum_aux (x::acc) (x+1) n
  in
  List.rev (enum_aux [] x n)

let rec take n xs =
  match (n,xs) with
  | (0,_) -> []
  | (_,[]) -> failwith "take: not enough"
  | (n,x::xs) -> x::take (n-1) xs


let last_n n l = List.rev (take n (List.rev l))
let last l = List.hd (last_n 1 l)


let (list_of_string: string -> char list) = function
    "" -> []
  | s -> (enum 0 ((String.length s) - 1) +> List.map (String.get s))

let (lines: string -> string list) = fun s ->
  let rec lines_aux = function
    | [] -> []
    | [x] -> if x = "" then [] else [x]
    | x::xs ->
        x::lines_aux xs
  in
  Str.split_delim (Str.regexp "\n") s +> lines_aux


let push2 v l =
  l := v :: !l

let debugger = ref false

let unwind_protect f cleanup =
  if !debugger then f() else
    try f ()
    with e -> begin cleanup e; raise e end

let finalize f cleanup =
  if !debugger then f() else
  try
    let res = f () in
    cleanup ();
    res
  with e ->
    cleanup ();
    raise e

let command2 s = ignore(Sys.command s)


let (matched: int -> string -> string) = fun i s ->
  Str.matched_group i s

let matched1 = fun s -> matched 1 s
let matched2 = fun s -> (matched 1 s, matched 2 s)
let matched3 = fun s -> (matched 1 s, matched 2 s, matched 3 s)
let matched4 = fun s -> (matched 1 s, matched 2 s, matched 3 s, matched 4 s)
let matched5 = fun s -> (matched 1 s, matched 2 s, matched 3 s, matched 4 s, matched 5 s)
let matched6 = fun s -> (matched 1 s, matched 2 s, matched 3 s, matched 4 s, matched 5 s, matched 6 s)
let matched7 = fun s -> (matched 1 s, matched 2 s, matched 3 s, matched 4 s, matched 5 s, matched 6 s, matched 7 s)

let (with_open_stringbuf: (((string -> unit) * Buffer.t) -> unit) -> string) =
 fun f ->
  let buf = Buffer.create 100 in
  let pr s = Buffer.add_string buf (s ^ "\n") in
  f (pr, buf);
  Buffer.contents buf


let foldl1 p = function x::xs -> List.fold_left p x xs | _ -> failwith "foldl1"

(*****************************************************************************)
(* Debugging/logging *)
(*****************************************************************************)

(* I used this in coccinelle where the huge logging of stuff ask for
 * a more organized solution that use more visual indentation hints.
 *
 * todo? could maybe use log4j instead ? or use Format module more
 * consistently ?
 *)

let _tab_level_print = ref 0
let _tab_indent = 5


let _prefix_pr = ref ""

let indent_do f =
  _tab_level_print := !_tab_level_print + _tab_indent;
  finalize f
   (fun () -> _tab_level_print := !_tab_level_print - _tab_indent;)


let pr s =
  print_string !_prefix_pr;
  do_n !_tab_level_print (fun () -> print_string " ");
  print_string s;
  print_string "\n";
  flush stdout

let pr_no_nl s =
  print_string !_prefix_pr;
  do_n !_tab_level_print (fun () -> print_string " ");
  print_string s;
  flush stdout






let _chan_pr2 = ref (None: out_channel option)

let out_chan_pr2 ?(newline=true) s =
  match !_chan_pr2 with
  | None -> ()
  | Some chan ->
      output_string chan (s ^ (if newline then "\n" else ""));
      flush chan

let print_to_stderr = ref true

let pr2 s =
  if !print_to_stderr
  then
    begin
      prerr_string !_prefix_pr;
      do_n !_tab_level_print (fun () -> prerr_string " ");
      prerr_string s;
      prerr_string "\n";
      flush stderr;
      out_chan_pr2 s;
      ()
    end

let pr2_no_nl s =
  if !print_to_stderr
  then
    begin
      prerr_string !_prefix_pr;
      do_n !_tab_level_print (fun () -> prerr_string " ");
      prerr_string s;
      flush stderr;
      out_chan_pr2 ~newline:false s;
      ()
    end


let pr_xxxxxxxxxxxxxxxxx () =
  pr "-----------------------------------------------------------------------"

let pr2_xxxxxxxxxxxxxxxxx () =
  pr2 "-----------------------------------------------------------------------"


let reset_pr_indent () =
  _tab_level_print := 0

(* old:
 * let pr s = (print_string s; print_string "\n"; flush stdout)
 * let pr2 s = (prerr_string s; prerr_string "\n"; flush stderr)
 *)

(* ---------------------------------------------------------------------- *)

(* I can not use the _xxx ref tech that I use for common_extra.ml here because
 * ocaml don't like the polymorphism of Dumper mixed with refs.
 *
 * let (_dump_func : ('a -> string) ref) = ref
 * (fun x -> failwith "no dump yet, have you included common_extra.cmo?")
 * let (dump : 'a -> string) = fun x ->
 * !_dump_func x
 *
 * So I have included directly dumper.ml in common.ml. It's more practical
 * when want to give script that use my common.ml, I just have to give
 * this file.
 *)

(* don't the code below, use the Dumper module in ocamlextra instead.
(* start of dumper.ml *)

(* Dump an OCaml value into a printable string.
 * By Richard W.M. Jones (rich@annexia.org).
 * dumper.ml 1.2 2005/02/06 12:38:21 rich Exp
 *)
open Printf
open Obj

let rec dump r =
  if is_int r then
    string_of_int (magic r : int)
  else (				(* Block. *)
    let rec get_fields acc = function
      | 0 -> acc
      | n -> let n = n-1 in get_fields (field r n :: acc) n
    in
    let rec is_list r =
      if is_int r then (
	if (magic r : int) = 0 then true (* [] *)
	else false
      ) else (
	let s = size r and t = tag r in
	if t = 0 && s = 2 then is_list (field r 1) (* h :: t *)
	else false
      )
    in
    let rec get_list r =
      if is_int r then []
      else let h = field r 0 and t = get_list (field r 1) in h :: t
    in
    let opaque name =
      (* XXX In future, print the address of value 'r'.  Not possible in
       * pure OCaml at the moment.
       *)
      "<" ^ name ^ ">"
    in

    let s = size r and t = tag r in

    (* From the tag, determine the type of block. *)
    if is_list r then ( (* List. *)
      let fields = get_list r in
      "[" ^ String.concat "; " (List.map dump fields) ^ "]"
    )
    else if t = 0 then (		(* Tuple, array, record. *)
      let fields = get_fields [] s in
      "(" ^ String.concat ", " (List.map dump fields) ^ ")"
    )

      (* Note that [lazy_tag .. forward_tag] are < no_scan_tag.  Not
       * clear if very large constructed values could have the same
       * tag. XXX *)
    else if t = lazy_tag then opaque "lazy"
    else if t = closure_tag then opaque "closure"
    else if t = object_tag then (	(* Object. *)
      let fields = get_fields [] s in
      let clasz, id, slots =
	match fields with h::h'::t -> h, h', t | _ -> assert false in
      (* No information on decoding the class (first field).  So just print
       * out the ID and the slots.
       *)
      "Object #" ^ dump id ^
      " (" ^ String.concat ", " (List.map dump slots) ^ ")"
    )
    else if t = infix_tag then opaque "infix"
    else if t = forward_tag then opaque "forward"

    else if t < no_scan_tag then (	(* Constructed value. *)
      let fields = get_fields [] s in
      "Tag" ^ string_of_int t ^
      " (" ^ String.concat ", " (List.map dump fields) ^ ")"
    )
    else if t = string_tag then (
      "\"" ^ String.escaped (magic r : string) ^ "\""
    )
    else if t = double_tag then (
      string_of_float (magic r : float)
    )
    else if t = abstract_tag then opaque "abstract"
    else if t = custom_tag then opaque "custom"
    else if t = final_tag then opaque "final"
    else failwith ("dump: impossible tag (" ^ string_of_int t ^ ")")
  )

let dump v = dump (repr v)

(* end of dumper.ml *)
*)

(*
let (dump : 'a -> string) = fun x ->
  Dumper.dump x
*)


(* ---------------------------------------------------------------------- *)
let pr2_gen x = pr2 (Dumper.dump x)



(* ---------------------------------------------------------------------- *)


let _already_printed = Hashtbl.create 101
let disable_pr2_once = ref false

let xxx_once f s =
  if !disable_pr2_once then pr2 s
  else
    if not (Hashtbl.mem _already_printed s)
    then begin
      Hashtbl.add _already_printed s true;
      f ("(ONCE) " ^ s)
    end

let pr2_once s = xxx_once pr2 s

let clear_pr2_once _ = Hashtbl.clear _already_printed

(* ---------------------------------------------------------------------- *)
let mk_pr2_wrappers aref =
  let fpr2 s =
    if !aref
    then pr2 s
    else
      (* just to the log file *)
      out_chan_pr2 s
  in
  let fpr2_once s =
    if !aref
    then pr2_once s
    else
      xxx_once out_chan_pr2 s
  in
    fpr2, fpr2_once

(* ---------------------------------------------------------------------- *)
(* could also be in File section *)

let redirect_stdout file f =
  begin
    let chan = open_out file in
    let descr = Unix.descr_of_out_channel chan in

    let saveout = Unix.dup Unix.stdout in
      Unix.dup2 descr Unix.stdout;
      flush stdout;
      let res = f() in
	flush stdout;
	Unix.dup2 saveout Unix.stdout;
	close_out chan;
	res
  end

let redirect_stdout_opt optfile f =
  match optfile with
    | None -> f()
    | Some outfile -> redirect_stdout outfile f

let redirect_stdout_stderr file f =
  begin
    let chan = open_out file in
    let descr = Unix.descr_of_out_channel chan in

    let saveout = Unix.dup Unix.stdout in
    let saveerr = Unix.dup Unix.stderr in
    Unix.dup2 descr Unix.stdout;
    Unix.dup2 descr Unix.stderr;
    flush stdout; flush stderr;
    f();
    flush stdout; flush stderr;
    Unix.dup2 saveout Unix.stdout;
    Unix.dup2 saveerr Unix.stderr;
    close_out chan;
  end

let redirect_stdin file f =
  begin
    let chan = open_in file in
    let descr = Unix.descr_of_in_channel chan in

    let savein = Unix.dup Unix.stdin in
    Unix.dup2 descr Unix.stdin;
    let res = f() in
    Unix.dup2 savein Unix.stdin;
    close_in chan;
    res
  end

let redirect_stdin_opt optfile f =
  match optfile with
  | None -> f()
  | Some infile -> redirect_stdin infile f


let spf = Printf.sprintf

(* ---------------------------------------------------------------------- *)

let _chan = ref stderr

let dolog s = output_string !_chan (s ^ "\n"); flush !_chan

let verbose_level = ref 1
let log s =  if !verbose_level >= 1 then dolog s
let log2 s = if !verbose_level >= 2 then dolog s

(* ---------------------------------------------------------------------- *)

let pause () = (pr2 "pause: type return"; ignore(read_line ()))

(* src: from getopt from frish *)
let wait () = Unix.sleep 1

(* was used by fix_caml *)
let _trace_var = ref 0
let add_var() = incr _trace_var
let dec_var() = decr _trace_var
let get_var() = !_trace_var

let (print_n: int -> string -> unit) = fun i s ->
  do_n i (fun () -> print_string s)
let (printerr_n: int -> string -> unit) = fun i s ->
  do_n i (fun () -> prerr_string s)

let _debug = ref true
let debug f = if !_debug then f () else ()



(* now in prelude:
 * let debugger = ref false
 *)


(*****************************************************************************)
(* Profiling *)
(*****************************************************************************)

type prof = PALL | PNONE | PSOME of string list
let profile = ref PNONE
let show_trace_profile = ref false

let check_profile category =
  match !profile with
    PALL -> true
  | PNONE -> false
  | PSOME l -> List.mem category l

let _profile_table = ref (Hashtbl.create 101)

let adjust_profile_entry category difftime =
  let (xtime, xcount) =
    (try Hashtbl.find !_profile_table category
    with Not_found ->
      let xtime = ref 0.0 in
      let xcount = ref 0 in
      Hashtbl.add !_profile_table category (xtime, xcount);
      (xtime, xcount)
    ) in
  xtime := !xtime +. difftime;
  xcount := !xcount + 1;
  ()

(* subtil: don't forget to give all arguments to f, otherwise partial app
 * and will profile nothing.
 *
 * todo: try also detect when complexity augment each time, so can
 * detect the situation for a function gets worse and worse ?
 *)
let profile_code category f =
  if not (check_profile category)
  then f()
  else begin
  if !show_trace_profile then pr2 (spf "p: %s" category);
  let t = Unix.gettimeofday () in
  let res, prefix =
    try Some (f ()), ""
    with Timeout -> None, "*"
  in
  let category = prefix ^ category in (* add a '*' to indicate timeout func *)
  let t' = Unix.gettimeofday () in

  adjust_profile_entry category (t' -. t);
  (match res with
  | Some res -> res
  | None -> raise Timeout
  );
  end


let _is_in_exclusif = ref (None: string option)

let profile_code_exclusif category f =
  if not (check_profile category)
  then f()
  else begin

  match !_is_in_exclusif with
  | Some s ->
      failwith (spf "profile_code_exclusif: %s but already in %s " category s);
  | None ->
      _is_in_exclusif := (Some category);
      finalize
        (fun () ->
          profile_code category f
        )
        (fun () ->
          _is_in_exclusif := None
        )

  end

let profile_code_inside_exclusif_ok category f =
  failwith "Todo"


(* todo: also put  % ? also add % to see if coherent numbers *)
let profile_diagnostic () =
  if !profile = PNONE then "" else
  let xs =
    Hashtbl.fold (fun k v acc -> (k,v)::acc) !_profile_table []
      +> List.sort (fun (k1, (t1,n1)) (k2, (t2,n2)) -> compare t2 t1)
    in
    with_open_stringbuf (fun (pr,_) ->
      pr "---------------------";
      pr "profiling result";
      pr "---------------------";
      xs +> List.iter (fun (k, (t,n)) ->
        pr (Printf.sprintf "%-40s : %10.3f sec %10d count" k !t !n)
      )
    )

let reset_profile _ =
  (if !profile <> PNONE
  then pr2 (profile_diagnostic ()));
  Hashtbl.clear !_profile_table

let report_if_take_time timethreshold s f =
  let t = Unix.gettimeofday () in
  let res = f () in
  let t' = Unix.gettimeofday () in
  if (t' -. t  > float_of_int timethreshold)
  then pr2 (Printf.sprintf "Note: processing took %7.1fs: %s" (t' -. t) s);
  res

(*****************************************************************************)
(* Test *)
(*****************************************************************************)
let example b = assert b

let _ex1 = example (enum 1 4 = [1;2;3;4])

let assert_equal a b =
  if not (a = b)
  then failwith ("assert_equal: those 2 values are not equal:\n\t" ^
                 (Dumper.dump a) ^ "\n\t" ^ (Dumper.dump b) ^ "\n")

let (example2: string -> bool -> unit) = fun s b ->
  try assert b with x -> failwith s

(*-------------------------------------------------------------------*)
let _list_bool = ref []

let (example3: string -> bool -> unit) = fun s b ->
 _list_bool := (s,b)::(!_list_bool)

(* could introduce a fun () otherwise the calculus is made at compile time
 * and this can be long. This would require to redefine test_all.
 *   let (example3: string -> (unit -> bool) -> unit) = fun s func ->
 *   _list_bool := (s,func):: (!_list_bool)
 *
 * I would like to do as a func that take 2 terms, and make an = over it
 * avoid to add this ugly fun (), but pb of type, can't do that :(
 *)


let (test_all: unit -> unit) = fun () ->
  List.iter (fun (s, b) ->
    Printf.printf "%s: %s\n" s (if b then "passed" else "failed")
  ) !_list_bool

let (test: string -> unit) = fun s ->
  Printf.printf "%s: %s\n" s
    (if (List.assoc s (!_list_bool)) then "passed" else "failed")

let _ex = example3 "@" ([1;2]@[3;4;5] = [1;2;3;4;5])

(*-------------------------------------------------------------------*)
(* Regression testing *)
(*-------------------------------------------------------------------*)

(* cf end of file. It uses too many other common functions so I
 * have put the code at the end of this file.
 *)



(* todo? take code from julien signoles in calendar-2.0.2/tests *)
(*

(* Generic functions used in the tests. *)

val reset : unit -> unit
val nb_ok : unit -> int
val nb_bug : unit -> int
val test : bool -> string -> unit
val test_exn : 'a Lazy.t -> string -> unit


let ok_ref = ref 0
let ok () = incr ok_ref
let nb_ok () = !ok_ref

let bug_ref = ref 0
let bug () = incr bug_ref
let nb_bug () = !bug_ref

let reset () =
  ok_ref := 0;
  bug_ref := 0

let test x s =
  if x then ok () else begin Printf.printf "%s\n" s; bug () end;;

let test_exn x s =
  try
    ignore (Lazy.force x);
    Printf.printf "%s\n" s;
    bug ()
  with _ ->
    ok ();;
*)


(*****************************************************************************)
(* Quickcheck like (sfl) *)
(*****************************************************************************)

(* Better than quickcheck, cos can't do a test_all_prop in haskell cos
 * prop were functions, whereas here we have not prop_Unix x = ... but
 * laws "unit" ...
 *
 * How to do without overloading ? objet ? can pass a generator as a
 * parameter, mais lourd, prefer automatic inferring of the
 * generator? But at the same time quickcheck does not do better cos
 * we must explicitly type the property. So between a
 *    prop_unit:: [Int] -> [Int] -> bool ...
 *    prop_unit x = reverse [x] == [x]
 * and
 *    let _ = laws "unit" (fun x -> reverse [x] = [x]) (listg intg)
 * there is no real differences.
 *
 * Yes I define typeg generator but quickcheck too, he must define
 * class instance. I emulate the context Gen a => Gen [a] by making
 * listg take as a param a type generator. Moreover I have not the pb of
 * monad. I can do random independently, so my code is more simple
 * I think than the haskell code of quickcheck.
 *
 * update: apparently Jane Street have copied some of my code for their
 * Ounit_util.ml and quichcheck.ml in their Core library :)
 *)

(*---------------------------------------------------------------------------*)
(* generators *)
(*---------------------------------------------------------------------------*)
type 'a gen = unit -> 'a

let (ig: int gen) = fun () ->
  Random.int 10
let (lg: ('a gen) -> ('a list) gen) = fun gen () ->
  foldn (fun acc i -> (gen ())::acc) [] (Random.int 10)
let (pg: ('a gen) -> ('b gen) -> ('a * 'b) gen) = fun gen1 gen2 () ->
  (gen1 (), gen2 ())
let polyg = ig
let (ng: (string gen)) = fun () ->
  "a" ^ (string_of_int (ig ()))

let (oneofl: ('a list) -> 'a gen) = fun xs () ->
  List.nth xs (Random.int (List.length xs))
(* let oneofl l = oneof (List.map always l) *)

let (oneof: (('a gen) list) -> 'a gen) = fun xs ->
  List.nth xs (Random.int (List.length xs))

let (always: 'a -> 'a gen) = fun e () -> e

let (frequency: ((int * ('a gen)) list) -> 'a gen) = fun xs ->
  let sums = sum_int (List.map fst xs) in
  let i = Random.int sums in
  let rec freq_aux acc = function
    | (x,g)::xs -> if i < acc+x then g else freq_aux (acc+x) xs
    | _ -> failwith "frequency"
  in
  freq_aux 0 xs
let frequencyl l = frequency (List.map (fun (i,e) -> (i,always e)) l)

(*
let b = oneof [always true; always false] ()
let b = frequency [3, always true; 2, always false] ()
*)

(* cannot do this:
 *    let rec (lg: ('a gen) -> ('a list) gen) = fun gen -> oneofl [[]; lg gen ()]
 * nor
 *    let rec (lg: ('a gen) -> ('a list) gen) = fun gen -> oneof [always []; lg gen]
 *
 * because caml is not as lazy as haskell :( fix the pb by introducing a size
 * limit. take the bounds/size as parameter. morover this is needed for
 * more complex type.
 *
 * how make a bintreeg ?? we need recursion
 *
 * let rec (bintreeg: ('a gen) -> ('a bintree) gen) = fun gen () ->
 * let rec aux n =
 * if n = 0 then (Leaf (gen ()))
 * else frequencyl [1, Leaf (gen ()); 4, Branch ((aux (n / 2)), aux (n / 2))]
 * ()
 * in aux 20
 *
 *)


(*---------------------------------------------------------------------------*)
(* property *)
(*---------------------------------------------------------------------------*)

(* todo: a test_all_laws, better syntax (done already a little with ig in
 * place of intg. En cas d'erreur, print the arg that not respect
 *
 * todo: with monitoring, as in haskell, laws = laws2, no need for 2 func,
 * but hard i found
 *
 * todo classify, collect, forall
 *)


(* return None when good, and Just the_problematic_case when bad *)
let (laws: string -> ('a -> bool) -> ('a gen) -> 'a option) = fun s func gen ->
  let res = foldn (fun acc i -> let n = gen() in (n, func n)::acc) [] 1000 in
  let res = List.filter (fun (x,b) -> not b) res in
  if res = [] then None else Some (fst (List.hd res))

let rec (statistic_number: ('a list) -> (int * 'a) list) = function
  | []    -> []
  | x::xs -> let (splitg, splitd) = List.partition (fun y -> y = x) xs in
    (1+(List.length splitg), x)::(statistic_number splitd)

(* in pourcentage *)
let (statistic: ('a list) -> (int * 'a) list) = fun xs ->
  let stat_num = statistic_number xs in
  let totals = sum_int (List.map fst stat_num) in
  List.map (fun (i, v) -> ((i * 100) / totals), v) stat_num

let (laws2:
        string -> ('a -> (bool * 'b)) -> ('a gen) ->
        ('a option * ((int * 'b) list ))) =
  fun s func gen ->
  let res = foldn (fun acc i -> let n = gen() in (n, func n)::acc) [] 1000 in
  let stat = statistic (List.map (fun (x,(b,v)) -> v) res) in
  let res = List.filter (fun (x,(b,v)) -> not b) res in
  if res = [] then (None, stat) else (Some (fst (List.hd res)), stat)


(*
let b = laws "unit" (fun x       -> reverse [x]          = [x]                   )ig
let b = laws "app " (fun (xs,ys) -> reverse (xs @ ys)     = reverse ys @ reverse xs)(pg (lg ig)(lg ig))
let b = laws "rev " (fun xs      -> reverse (reverse xs) = xs                    )(lg ig)
let b = laws "appb" (fun (xs,ys) -> reverse (xs @ ys)     = reverse xs @ reverse ys)(pg (lg ig)(lg ig))
let b = laws "max"  (fun (x,y)   -> x <= y ==> (max x y  = y)                       )(pg ig ig)

let b = laws2 "max"  (fun (x,y)   -> ((x <= y ==> (max x y  = y)), x <= y))(pg ig ig)
*)


(* todo, do with coarbitrary ?? idea is that given a 'a, generate a 'b
 * depending of 'a and gen 'b, that is modify gen 'b, what is important is
 * that each time given the same 'a, we must get the same 'b !!!
 *)

(*
let (fg: ('a gen) -> ('b gen) -> ('a -> 'b) gen) = fun gen1 gen2 () ->
let b = laws "funs" (fun (f,g,h) -> x <= y ==> (max x y  = y)       )(pg ig ig)
 *)

(*
let one_of xs = List.nth xs (Random.int (List.length xs))
let take_one xs =
  if xs=[] then failwith "Take_one: empty list"
  else
    let i = Random.int (List.length xs) in
    List.nth xs i, filter_index (fun j _ -> i <> j) xs
*)

(*****************************************************************************)
(* Persistence *)
(*****************************************************************************)

let get_value filename =
  let chan = open_in filename in
  let x = input_value chan in (* <=> Marshal.from_channel  *)
  (close_in chan; x)

let write_value valu filename =
  let chan = open_out filename in
  (output_value chan valu;  (* <=> Marshal.to_channel *)
   (* Marshal.to_channel chan valu [Marshal.Closures]; *)
   close_out chan)

let read_value f = get_value f


let marshal__to_string2 v flags =
  Marshal.to_string v flags
let marshal__to_string a b =
  profile_code "Marshalling" (fun () -> marshal__to_string2 a b)

let marshal__from_string2 v flags =
  Marshal.from_string v flags
let marshal__from_string a b =
  profile_code "Marshalling" (fun () -> marshal__from_string2 a b)



(*****************************************************************************)
(* Counter *)
(*****************************************************************************)
let _counter = ref 0
let counter () = (_counter := !_counter +1; !_counter)

let _counter2 = ref 0
let counter2 () = (_counter2 := !_counter2 +1; !_counter2)

let _counter3 = ref 0
let counter3 () = (_counter3 := !_counter3 +1; !_counter3)

type timestamp = int

(*****************************************************************************)
(* String_of *)
(*****************************************************************************)
(* To work with the macro system autogenerated string_of and print_ function
   (kind of deriving a la haskell) *)

(* int, bool, char, float, ref ?, string *)

(* specialized
let (string_of_list: char list -> string) =
  List.fold_left (fun acc x -> acc^(Char.escaped x)) ""
*)


let rec print_between between fn = function
  | [] -> ()
  | [x] -> fn x
  | x::xs -> fn x; between(); print_between between fn xs




let adjust_pp_with_indent f =
  Format.open_box !_tab_level_print;
  (*Format.force_newline();*)
  f();
  Format.close_box ();
  Format.print_newline()

let adjust_pp_with_indent_and_header s f =
  Format.open_box (!_tab_level_print + String.length s);
  do_n !_tab_level_print (fun () -> Format.print_string " ");
  Format.print_string s;
  f();
  Format.close_box ();
  Format.print_newline()



let pp_do_in_box f      = Format.open_box 1; f(); Format.close_box ()
let pp_do_in_zero_box f = Format.open_box 0; f(); Format.close_box ()

let pp s = Format.print_string s


(* julia: convert something printed using format to print into a string *)
(* now at bottom of file
let format_to_string f =
 ...
*)

(*****************************************************************************)
(* Composition/Control *)
(*****************************************************************************)

(* I like the obj.func object notation. In OCaml cannot use '.' so I use +>
 *
 * update: it seems that F# agrees with me :) but they use |>
 *)

(* now in prelude:
 * let (+>) o f = f o
 *)
let (+!>) refo f = refo := f !refo
(* alternatives:
 *  let ((@): 'a -> ('a -> 'b) -> 'b) = fun a b -> b a
 *  let o f g x = f (g x)
 *)

let ($)     f g x = g (f x)
let compose f g x = f (g x)
(* don't work :( let ( \B0 ) f g x = f(g(x)) *)

(* trick to have something similar to the   1 `max` 4   haskell infix notation.
   by Keisuke Nakano on the caml mailing list.
>    let ( /* ) x y = y x
>    and ( */ ) x y = x y
or
  let ( <| ) x y = y x
  and ( |> ) x y = x y

> Then we can make an infix operator <| f |> for a binary function f.
*)

let flip f = fun a b -> f b a

let curry f x y = f (x,y)
let uncurry f (a,b) = f a b

let id = fun x -> x

let rec applyn n f o = if n = 0 then o else applyn (n-1) f (f o)

class ['a] shared_variable_hook (x:'a) =
  object(self)
    val mutable data = x
    val mutable registered = []
    method set x =
      begin
        data <- x;
        pr "refresh registered";
        registered +> List.iter (fun f -> f());
      end
    method get = data
    method modify f = self#set (f self#get)
    method register f =
      registered <- f :: registered
  end

(* src: from aop project. was called ptFix *)
let rec fixpoint trans elem =
  let image = trans elem in
  if (image = elem)
  then elem (* point fixe *)
  else fixpoint trans image

(* le point fixe  pour les objets. was called ptFixForObjetct *)
let rec fixpoint_for_object trans elem =
  let image = trans elem in
  if (image#equal elem) then elem (* point fixe *)
  else fixpoint_for_object trans image

let (add_hook: ('a -> ('a -> 'b) -> 'b) ref  -> ('a -> ('a -> 'b) -> 'b) -> unit) =
 fun var f ->
  let oldvar = !var in
  var := fun arg k -> f arg (fun x -> oldvar x k)

let (add_hook_action: ('a -> unit) ->   ('a -> unit) list ref -> unit) =
 fun f hooks ->
  push2 f hooks

let (run_hooks_action: 'a -> ('a -> unit) list ref -> unit) =
 fun obj hooks ->
  !hooks +> List.iter (fun f -> try f obj with _ -> ())


type 'a mylazy = (unit -> 'a)

(* a la emacs *)
let save_excursion reference f =
  let old = !reference in
  let res = try f() with e -> reference := old; raise e in
  reference := old;
  res

let memoized h k f =
  try Hashtbl.find h k
  with Not_found ->
    let v = f () in
    begin
      Hashtbl.add h k v;
      v
    end

let once f =
  let already = ref false in
  (fun x ->
    if not !already
    then begin already := true; f x end
  )

(* cache_file, cf below *)

(* finalize, cf prelude *)


(* cheat *)
let rec y f = fun x -> f (y f) x

(*****************************************************************************)
(* Error management *)
(*****************************************************************************)

exception Todo
exception Impossible of int
exception Here
exception ReturnExn

exception Multi_found (* to be consistent with Not_found *)

exception WrongFormat of string

(* old: let _TODO () = failwith "TODO",  now via fix_caml with raise Todo *)

let internal_error s = failwith ("internal error: "^s)
let error_cant_have x = internal_error ("can't have this case: " ^(Dumper.dump x))



(* before warning I was forced to do stuff like this:
 *
 * let (fixed_int_to_posmap: fixed_int -> posmap) = fun fixed ->
 * let v = ((fix_to_i fixed) / (power 2 16)) in
 * let _ = Printf.printf "coord xy = %d\n" v in
 * v
 *
 * The need for printf make me force to name stuff :(
 * How avoid ? use 'it' special keyword ?
 * In fact don't have to name it, use +> (fun v -> ...)  so when want
 * erase debug just have to erase one line.
 *)
let warning s v = (pr2 ("Warning: " ^ s ^ "; value = " ^ (Dumper.dump v)); v)

(* want or of merd, but cannot cos cannot put die ... in b (strict call) *)
let (|||) a b = try a with _ -> b

(* emacs/lisp inspiration, (vouillon does that too in unison I think) *)

(* now in Prelude:
 * let unwind_protect f cleanup = ...
 * let finalize f cleanup =  ...
 *)

(* sometimes to get help from ocaml compiler to tell me places where
 * I should update, we sometimes need to change some type from pair
 * to triple, hence this kind of fake type.
 *)
type evotype = unit
let evoval = ()

(*****************************************************************************)
(* Environment *)
(*****************************************************************************)

let check_stack = ref true
let check_stack_size limit =
  if !check_stack then begin
    pr2 "checking stack size (do ulimit -s 50000 if problem)";
    let rec aux i =
      if i = limit
      then 0
      else 1 + aux (i + 1)
    in
    assert(aux 0 = limit);
    ()
  end

let test_check_stack_size limit =
  (* bytecode: 100000000 *)
  (* native:   10000000 *)
  check_stack_size (int_of_string limit)


(* only relevant in bytecode, in native the stacklimit is the os stacklimit
 * (adjustable by ulimit -s)
 *)
let _init_gc_stack =
  Gc.set {(Gc.get ()) with Gc.stack_limit = 100 * 1024 * 1024}




(* if process a big set of files then don't want get overflow in the middle
 * so for this we are ready to spend some extra time at the beginning that
 * could save far more later.
 *)
let check_stack_nbfiles nbfiles =
  if nbfiles > 200
  then check_stack_size 10000000

(*****************************************************************************)
(* Arguments/options and command line (cocci and acomment) *)
(*****************************************************************************)

(*
 * Why define wrappers ? Arg not good enough ? Well the Arg.Rest is not that
 * good and I need a way sometimes to get a list of argument.
 *
 * I could define maybe a new Arg.spec such as
 * | String_list of (string list -> unit), but the action may require
 * some flags to be set, so better to process this after all flags have
 * been set by parse_options. So have to split. Otherwise it would impose
 * an order of the options such as
 * -verbose_parsing -parse_c file1 file2. and I really like to use bash
 * history and add just at the end of my command a -profile for instance.
 *
 *
 * Why want a -action arg1 arg2 arg3 ? (which in turn requires this
 * convulated scheme ...) Why not use Arg.String action such as
 * "-parse_c", Arg.String (fun file -> ...) ?
 * I want something that looks like ocaml function but at the UNIX
 * command line level. So natural to have this scheme instead of
 * -taxo_file arg2 -sample_file arg3 -parse_c arg1.
 *
 *
 * Why not use the toplevel ?
 * - because to debug, ocamldebug is far superior to the toplevel
 *   (can go back, can go directly to a specific point, etc).
 *   I want a kind of testing at cmdline level.
 * - Also I don't have file completion when in the ocaml toplevel.
 *   I have to type "/path/to/xxx" without help.
 *
 *
 * Why having variable flags ? Why use 'if !verbose_parsing then ...' ?
 * why not use strings and do stuff like the following
 * 'if (get_config "verbose_parsing") then ...'
 * Because I want to make the interface for flags easier for the code
 * that use it. The programmer should not be bothered whether this
 * flag is set via args cmd line or a config file, so I want to make it
 * as simple as possible, just use a global plain caml ref variable.
 *
 * Same spirit a little for the action. Instead of having function such as
 * test_parsing_c, I could do it only via string. But I still prefer
 * to have plain caml test functions. Also it makes it easier to call
 * those functions from a toplevel for people who prefer the toplevel.
 *
 *
 * So have flag_spec and action_spec. And in flag have debug_xxx flags,
 * verbose_xxx flags and other flags.
 *
 * I would like to not have to separate the -xxx actions spec from the
 * corresponding actions, but those actions may need more than one argument
 * and so have to wait for parse_options, which in turn need the options
 * spec, so circle.
 *
 * Also I don't want to mix code with data structures, so it's better that the
 * options variable contain just a few stuff and have no side effects except
 * setting global variables.
 *
 * Why not have a global variable such as Common.actions that
 * other modules modify ? No, I prefer to do less stuff behind programmer's
 * back so better to let the user merge the different options at call
 * site, but at least make it easier by providing shortcut for set of options.
 *
 *
 *
 *
 * todo? isn't unison or scott-mcpeak-lib-in-cil handles that kind of
 * stuff better ? That is the need to localize command line argument
 * while still being able to gathering them. Same for logging.
 * Similar to the type prof = PALL | PNONE | PSOME of string list.
 * Same spirit of fine grain config in log4j ?
 *
 * todo? how mercurial/cvs/git manage command line options ? because they
 * all have a kind of DSL around arguments with some common options,
 * specific options, conventions, etc.
 *
 *
 * todo? generate the corresponding noxxx options ?
 * todo? generate list of options and show their value ?
 *
 * todo? make it possible to set this value via a config file ?
 *
 *
 *)

type arg_spec_full = Arg.key * Arg.spec * Arg.doc
type cmdline_options = arg_spec_full list

(* the format is a list of triples:
 *  (title of section * (optional) explanation of sections * options)
 *)
type options_with_title = string * string * arg_spec_full list
type cmdline_sections = options_with_title list


(* ---------------------------------------------------------------------- *)

(* now I use argv as I like at the call sites to show that
 * this function internally use argv.
 *)
let parse_options options usage_msg argv =
  let args = ref [] in
  (try
    Arg.parse_argv argv options (fun file -> args := file::!args) usage_msg;
    args := List.rev !args;
    !args
  with
  | Arg.Bad msg -> Printf.eprintf "%s" msg; exit 2
  | Arg.Help msg -> Printf.printf "%s" msg; exit 0
  )




let usage usage_msg options  =
  pr (Arg.usage_string (Arg.align options) usage_msg)


(* for coccinelle *)

(* If you don't want the -help and --help that are appended by Arg.align *)
let arg_align2 xs =
  Arg.align xs +> List.rev +> drop 2 +> List.rev


let short_usage usage_msg  ~short_opt =
  usage usage_msg short_opt

let long_usage  usage_msg  ~short_opt ~long_opt  =
  pr usage_msg;
  pr "";
  let all_options_with_title =
    (("main options", "", short_opt)::long_opt) in
  all_options_with_title +> List.iter
    (fun (title, explanations, xs) ->
      pr title;
      pr_xxxxxxxxxxxxxxxxx();
      if explanations <> ""
      then begin pr explanations; pr "" end;
      arg_align2 xs +> List.iter (fun (key,action,s) ->
        pr ("  " ^ key ^ s)
      );
      pr "";
    );
  ()

(* ---------------------------------------------------------------------- *)
(* kind of unit testing framework, or toplevel like functionality
 * at shell command line. I realize than in fact It follows a current trend
 * to have a main cmdline program where can then select different actions,
 * as in cvs/hg/git where do  hg <action> <arguments>, and the shell even
 * use a curried syntax :)
 *
 *
 * Not-perfect-but-basic-feels-right: an action
 * spec looks like this:
 *
 *    let actions () = [
 *      "-parse_taxo", "   <file>",
 *      Common.mk_action_1_arg test_parse_taxo;
 *      ...
 *     ]
 *
 * Not-perfect-but-basic-feels-right because for such functionality we
 * need a way to transform a string into a caml function and pass arguments
 * and the preceding design does exactly that, even if then the
 * functions that use this design are not so convenient to use (there
 * are 2 places where we need to pass those data, in the options and in the
 * main dispatcher).
 *
 * Also it's not too much intrusive. Still have an
 * action ref variable in the main.ml and can still use the previous
 * simpler way to do where the match args with in main.ml do the
 * dispatch.
 *
 * Use like this at option place:
 *   (Common.options_of_actions actionref (Test_parsing_c.actions())) @
 * Use like this at dispatch action place:
 *   | xs when List.mem !action (Common.action_list all_actions) ->
 *        Common.do_action !action xs all_actions
 *
 *)

type flag_spec   = Arg.key * Arg.spec * Arg.doc
type action_spec = Arg.key * Arg.doc * action_func
   and action_func = (string list -> unit)

type cmdline_actions = action_spec list
exception WrongNumberOfArguments

let options_of_actions action_ref actions =
  actions +> List.map (fun (key, doc, _func) ->
    (key, (Arg.Unit (fun () -> action_ref := key)), doc)
  )

let (action_list: cmdline_actions -> Arg.key list) = fun xs ->
  List.map (fun (a,b,c) -> a) xs

let (do_action: Arg.key -> string list (* args *) -> cmdline_actions -> unit) =
  fun key args xs ->
    let assoc = xs +> List.map (fun (a,b,c) -> (a,c)) in
    let action_func = List.assoc key assoc in
    action_func args


(* todo? if have a function with default argument ? would like a
 *  mk_action_0_or_1_arg ?
 *)

let mk_action_0_arg f =
  (function
  | [] -> f ()
  | _ -> raise WrongNumberOfArguments
  )

let mk_action_1_arg f =
  (function
  | [file] -> f file
  | _ -> raise WrongNumberOfArguments
  )

let mk_action_2_arg f =
  (function
  | [file1;file2] -> f file1 file2
  | _ -> raise WrongNumberOfArguments
  )

let mk_action_n_arg f = f

(*###########################################################################*)
(* And now basic types *)
(*###########################################################################*)



(*****************************************************************************)
(* Bool *)
(*****************************************************************************)
let (==>) b1 b2 = if b1 then b2 else true (* could use too => *)

(* superseded by another <=> below
let (<=>) a b = if a = b then 0 else if a < b then -1 else 1
*)


(*****************************************************************************)
(* Char *)
(*****************************************************************************)

let string_of_char c = String.make 1 c

let is_single  = String.contains ",;()[]{}_`"
let is_symbol  = String.contains "!@#$%&*+./<=>?\\^|:-~"
let is_space   = String.contains "\n\t "
let cbetween min max c =
  (int_of_char c) <= (int_of_char max) &&
  (int_of_char c) >= (int_of_char min)
let is_upper = cbetween 'A' 'Z'
let is_lower = cbetween 'a' 'z'
let is_digit = cbetween '0' '9'

let string_of_chars cs = cs +> List.map (String.make 1) +> String.concat ""



(*****************************************************************************)
(* Num *)
(*****************************************************************************)

(* since 3.08, div by 0 raise Div_by_rezo, and not anymore a hardware trap :)*)
let (/!) x y = if y = 0 then (log "common.ml: div by 0"; 0) else x / y

(* now in prelude
 * let rec (do_n: int -> (unit -> unit) -> unit) = fun i f ->
 * if i = 0 then () else (f(); do_n (i-1) f)
 *)

(* now in prelude
 * let rec (foldn: ('a -> int -> 'a) -> 'a -> int -> 'a) = fun f acc i ->
 * if i = 0 then acc else foldn f (f acc i) (i-1)
 *)

let sum_float = List.fold_left (+.) 0.0
let sum_int   = List.fold_left (+) 0

let pi  = 3.14159265358979323846
let pi2 = pi /. 2.0
let pi4 = pi /. 4.0

(* 180 = pi *)
let (deg_to_rad: float -> float) = fun deg ->
  (deg *. pi) /. 180.0

let clampf = function
  | n when n < 0.0 -> 0.0
  | n when n > 1.0 -> 1.0
  | n -> n

let square x = x *. x

let rec power x n = if n = 0 then 1 else x * power x (n-1)

let between i min max = i > min && i < max

let (between_strict: int -> int -> int -> bool) = fun a b c ->
  a < b && b < c

(* descendant *)
let (prime1: int -> int option)  = fun x ->
  let rec prime1_aux n =
    if n = 1 then None
    else
      if (x / n) * n = x then Some n else prime1_aux (n-1)
  in if x = 1 then None else if x < 0 then failwith "negative" else prime1_aux (x-1)

(* montant, better *)
let (prime: int -> int option)  = fun x ->
  let rec prime_aux n =
    if n = x then None
    else
      if (x / n) * n = x then Some n else prime_aux (n+1)
  in if x = 1 then None else if x < 0 then failwith "negative" else prime_aux 2

let sum xs = List.fold_left (+) 0 xs
let product = List.fold_left ( * ) 1


let decompose x =
  let rec decompose x =
  if x = 1 then []
  else
    (match prime x with
    | None -> [x]
    | Some n -> n::decompose (x / n)
    )
  in assert (product (decompose x) = x); decompose x

let sqr a = a *. a


type compare = Equal | Inf | Sup
let (<=>) a b = if a = b then Equal else if a < b then Inf else Sup
let (<==>) a b = if a = b then 0 else if a < b then -1 else 1

type uint = int


let int_of_base s base =
  fold_left_with_index (fun acc e i ->
    let j = Char.code e - Char.code '0' in
    if j >= base then failwith "not in good base"
    else acc + (j*(power base i))
		       )
    0  (List.rev (list_of_string s))

let int_of_stringbits s = int_of_base s 2
let _ = example (int_of_stringbits "1011" = 1*8 + 1*2 + 1*1)

let int_of_octal s = int_of_base s 8
let _ = example (int_of_octal "017" = 15)

(* let int_of_hex s = int_of_base s 16, NONONONO cos 'A' - '0' does not give 10 !! *)

let (+=) ref v = ref := !ref + v
let (-=) ref v = ref := !ref - v

let pourcent x total =
  (x * 100) / total

(*****************************************************************************)
(* Numeric/overloading *)
(*****************************************************************************)

type 'a numdict =
    NumDict of (('a-> 'a -> 'a) *
		('a-> 'a -> 'a) *
		('a-> 'a -> 'a) *
		('a -> 'a));;

let add (NumDict(a, m, d, n)) = a;;
let mul (NumDict(a, m, d, n)) = m;;
let div (NumDict(a, m, d, n)) = d;;
let neg (NumDict(a, m, d, n)) = n;;

let numd_int   = NumDict(( + ),( * ),( / ),( ~- ));;
let numd_float = NumDict(( +. ),( *. ), ( /. ),( ~-. ));;


module ArithFloatInfix = struct
    let (+..) = (+)
    let (-..) = (-)
    let (/..) = (/)
    let ( *.. ) = ( * )


    let (+) = (+.)
    let (-) = (-.)
    let (/) = (/.)
    let ( * ) = ( *. )

    let (+=) ref v = ref := !ref + v
    let (-=) ref v = ref := !ref - v

end



(*****************************************************************************)
(* Tuples *)
(*****************************************************************************)

type 'a pair = 'a * 'a
type 'a triple = 'a * 'a * 'a

let fst3 (x,_,_) = x
let snd3 (_,y,_) = y
let thd3 (_,_,z) = z

let pair  f (x,y) = (f x, f y)

(* for my ocamlbeautify script *)
let snd = snd
let fst = fst

let double a = a,a
let swap (x,y) = (y,x)

let tol_error n l = Printf.sprintf "tuple_of_list%d: found %d elements, expected %d" n (List.length l) n
let tuple_of_list1 = function [a] -> a | l -> failwith (tol_error 1 l)
let tuple_of_list2 = function [a;b] -> a,b | l -> failwith (tol_error 2 l)
let tuple_of_list3 = function [a;b;c] -> a,b,c | l -> failwith (tol_error 3 l)
let tuple_of_list4 = function [a;b;c;d] -> a,b,c,d | l -> failwith (tol_error 4 l)
let tuple_of_list5 = function [a;b;c;d;e] -> a,b,c,d,e | l -> failwith (tol_error 5 l)
let tuple_of_list6 = function [a;b;c;d;e;f] -> a,b,c,d,e,f | l -> failwith (tol_error 6 l)
let tuple_of_list7 = function [a;b;c;d;e;f;g] -> a,b,c,d,e,f,g | l -> failwith (tol_error 7 l)


(*****************************************************************************)
(* Maybe *)
(*****************************************************************************)

(* type 'a maybe  = Just of 'a | None *)

type ('a,'b) either = Left of 'a | Right of 'b
  (* with sexp *)
type ('a, 'b, 'c) either3 = Left3 of 'a | Middle3 of 'b | Right3 of 'c
  (* with sexp *)

let just = function
  | (Some x) -> x
  | _ -> failwith "just: pb"

let some = just


let fmap f = function
  | None -> None
  | Some x -> Some (f x)
let map_option = fmap

let equal_option sub_equal o o' =
  match o, o' with
    None, None -> true
  | Some x, Some x' -> sub_equal x x'
  | None, Some _
  | Some _, None -> false

let default d f = function
    None -> d
  | Some x -> f x

let do_option f = default () f

let optionise f =
  try Some (f ()) with Not_found -> None



(* pixel *)
let some_or = function
  | None -> id
  | Some e -> fun _ -> e


let partition_either f l =
  let rec part_either left right = function
  | [] -> (List.rev left, List.rev right)
  | x :: l ->
      (match f x with
      | Left  e -> part_either (e :: left) right l
      | Right e -> part_either left (e :: right) l) in
  part_either [] [] l

(* pixel *)
let rec filter_some = function
  | [] -> []
  | None :: l -> filter_some l
  | Some e :: l -> e :: filter_some l

let map_filter f xs = filter_some (List.map f xs)

(* avoid recursion *)
let tail_map_filter f xs =
  List.rev
    (List.fold_left
       (function prev ->
	 function cur ->
	   match f cur with
	     Some x -> x :: prev
	   | None -> prev)
       [] xs)

let rec find_some p = function
  | [] -> raise Not_found
  | x :: l ->
      match p x with
      |	Some v -> v
      |	None -> find_some p l

(* same
let map_find f xs =
  xs +> List.map f +> List.find (function Some x -> true | None -> false)
    +> (function Some x -> x | None -> raise Impossible)
*)


(*****************************************************************************)
(* TriBool *)
(*****************************************************************************)

type bool3 = True3 | False3 | TrueFalsePb3 of string



(*****************************************************************************)
(* Regexp, can also use PCRE *)
(*****************************************************************************)

(* Note: OCaml Str regexps are different from Perl regexp:
 *  - The OCaml regexp must match the entire way.
 *    So  "testBee" =~ "Bee" is wrong
 *    but "testBee" =~ ".*Bee" is right
 *    Can have the perl behavior if use  Str.search_forward instead of
 *    Str.string_match.
 *  - Must add some additional \ in front of some special char. So use
 *    \\( \\|  and also \\b
 *  - It does not always handle newlines very well.
 *  - \\b does consider _ but not numbers in indentifiers.
 *
 * Note: PCRE regexps are then different from Str regexps ...
 *  - just use '(' ')' for grouping, not '\\)'
 *  - still need \\b for word boundary, but this time it works ...
 *    so can match some word that have some digits in them.
 *
 *)

(* put before String section because String section use some =~ *)

(* let gsubst = global_replace *)


let (==~) s re = Str.string_match re s 0

let _memo_compiled_regexp = Hashtbl.create 101
let candidate_match_func s re =
  (* old: Str.string_match (Str.regexp re) s 0 *)
  let compile_re =
    memoized _memo_compiled_regexp re (fun () -> Str.regexp re)
  in
  Str.string_match compile_re s 0

let match_func s re =
  profile_code "Common.=~" (fun () -> candidate_match_func s re)

let (=~) s re =
  match_func s re





let string_match_substring re s =
  try let _i = Str.search_forward re s 0 in true
  with Not_found -> false

let _ =
  example(string_match_substring (Str.regexp "foo") "a foo b")
let _ =
  example(string_match_substring (Str.regexp "\\bfoo\\b") "a foo b")
let _ =
  example(string_match_substring (Str.regexp "\\bfoo\\b") "a\n\nfoo b")
let _ =
  example(string_match_substring (Str.regexp "\\bfoo_bar\\b") "a\n\nfoo_bar b")
(* does not work :(
let _ =
  example(string_match_substring (Str.regexp "\\bfoo_bar2\\b") "a\n\nfoo_bar2 b")
*)



let (regexp_match: string -> string -> string) = fun s re ->
  assert(s =~ re);
  Str.matched_group 1 s

(* beurk, side effect code, but hey, it is convenient *)
(* now in prelude
 * let (matched: int -> string -> string) = fun i s ->
 *    Str.matched_group i s
 *
 * let matched1 = fun s -> matched 1 s
 * let matched2 = fun s -> (matched 1 s, matched 2 s)
 * let matched3 = fun s -> (matched 1 s, matched 2 s, matched 3 s)
 * let matched4 = fun s -> (matched 1 s, matched 2 s, matched 3 s, matched 4 s)
 * let matched5 = fun s -> (matched 1 s, matched 2 s, matched 3 s, matched 4 s, matched 5 s)
 * let matched6 = fun s -> (matched 1 s, matched 2 s, matched 3 s, matched 4 s, matched 5 s, matched 6 s)
 *)



let split sep s = Str.split (Str.regexp sep) s
let _ = example ((split "/" "") = [])
(*
let rec join str = function
  | [] -> ""
  | [x] -> x
  | x::xs -> x ^ str ^ (join str xs)
*)


let (split_list_regexp: string -> string list -> (string * string list) list) =
 fun re xs ->
  let rec split_lr_aux (heading, accu) = function
    | [] -> [(heading, List.rev accu)]
    | x::xs ->
        if x =~ re
        then (heading, List.rev accu)::split_lr_aux (x, []) xs
        else split_lr_aux (heading, x::accu) xs
  in
  split_lr_aux ("__noheading__", []) xs
  +> (fun xs -> if List.hd xs = ("__noheading__",[]) then List.tl xs else xs)



let regexp_alpha =  Str.regexp
  "^[a-zA-Z_][A-Za-z_0-9]*$"

let regexp_int =  Str.regexp
  "^[0-9]+$"

let all_match re s =
  let regexp = Str.regexp re in
  let res = ref [] in
  let _ = Str.global_substitute regexp (fun _s ->
    let substr = Str.matched_string s in
    assert(substr ==~ regexp); (* @Effect: also use it's side effect *)
    let paren_matched = matched1 substr in
    push2 paren_matched res;
    "" (* @Dummy *)
  ) s in
  List.rev !res

let _ = example (all_match "\\(@[A-Za-z]+\\)" "ca va @Et toi @Comment"
                  = ["@Et";"@Comment"])


let regexp_word_str =
  "\\([a-zA-Z_][A-Za-z_0-9]*\\)"
let regexp_word = Str.regexp regexp_word_str

(*****************************************************************************)
(* Strings *)
(*****************************************************************************)

(* strings take space in memory. Better when can share the space used by
   similar strings *)
let _shareds = Hashtbl.create 100
let (shared_string: string -> string) = fun s ->
  try Hashtbl.find _shareds s
  with Not_found -> (Hashtbl.add _shareds s s; s)

let chop = function
  | "" -> ""
  | s -> String.sub s 0 (String.length s - 1)


let chop_dirsymbol = function
  | s when s =~ "\\(.*\\)/$" -> matched1 s
  | s -> s


let (<!!>) s (i,j) =
  String.sub s i (if j < 0 then String.length s - i + j + 1 else j - i)
(* let _ = example  ( "tototati"<!!>(3,-2) = "otat" ) *)

let (<!>) s i = String.get s i

(* pixel *)

let quote s = "\"" ^ s ^ "\""

(* done in summer 2007 for julia
 * Reference: P216 of gusfeld book
 * For two strings S1 and S2, D(i,j) is defined to be the edit distance of S1[1..i] to S2[1..j]
 * So edit distance of S1 (of length n) and S2 (of length m) is D(n,m)
 *
 * Dynamic programming technique
 * base:
 * D(i,0) = i  for all i (cos to go from S1[1..i] to 0 characters of S2 you have to delete all characters from S1[1..i]
 * D(0,j) = j  for all j (cos j characters must be inserted)
 * recurrence:
 * D(i,j) = min([D(i-1, j)+1, D(i, j - 1 + 1), D(i-1, j-1) + t(i,j)])
 * where t(i,j) is equal to 1 if S1(i) != S2(j) and  0 if equal
 * intuition = there is 4 possible action =  deletion, insertion, substitution, or match
 * so Lemma =
 *
 * D(i,j) must be one of the three
 *  D(i, j-1) + 1
 *  D(i-1, j)+1
 *  D(i-1, j-1) +
 *  t(i,j)
 *
 *
 *)
let matrix_distance s1 s2 =
  let n = (String.length s1) in
  let m = (String.length s2) in
  let mat = Array.make_matrix (n+1) (m+1) 0 in
  let t i j =
    if String.get s1 (i-1) = String.get s2 (j-1)
    then 0
    else 1
  in
  let min3 a b c = min (min a b) c in

  begin
    for i = 0 to n do
      mat.(i).(0) <- i
    done;
    for j = 0 to m do
      mat.(0).(j) <- j;
    done;
    for i = 1 to n do
      for j = 1 to m do
        mat.(i).(j) <-
          min3 (mat.(i).(j-1) + 1) (mat.(i-1).(j) + 1) (mat.(i-1).(j-1) + t i j)
      done
    done;
    mat
  end
let edit_distance s1 s2 =
  (matrix_distance s1 s2).(String.length s1).(String.length s2)


let test = edit_distance "vintner" "writers"
let _ = assert (edit_distance "winter" "winter" = 0)
let _ = assert (edit_distance "vintner" "writers" = 5)


(*****************************************************************************)
(* Filenames *)
(*****************************************************************************)

type filename = string (* TODO could check that exist :) type sux *)
  (* with sexp *)
type dirname = string (* TODO could check that exist :) type sux *)
  (* with sexp *)

module BasicType = struct
  type filename = string
end


let (filesuffix: filename -> string) = fun s ->
  (try regexp_match s "^[^\\.]+\\.\\([\\.a-zA-Z0-9_]+\\)$" with _ ->  "NOEXT")
  (* considers double extensions such as in.h or h.in to be the suffix *)
let (fileprefix: filename -> string) = fun s ->
  (try regexp_match s "\\(.+\\)\\.\\([a-zA-Z0-9_]+\\)?$" with _ ->  s)
  (* does not consider double extensions to be the suffix *)

let _ = example (filesuffix "toto.c" = "c")
let _ = example (filesuffix "toto.in.h" = "in.h")
let _ = example (fileprefix "toto.c" = "toto")
let _ = example (fileprefix "toto.in.h" = "toto.in")

(*
assert (s = fileprefix s ^ filesuffix s)

let withoutExtension s = global_replace (regexp "\\..*$") "" s
let () = example "without"
    (withoutExtension "toto.s.toto" = "toto")
*)

let adjust_ext_if_needed filename ext =
  if String.get ext 0 <> '.'
  then failwith "I need an extension such as .c not just c";

  if not (filename =~ (".*\\" ^ ext))
  then
    if Sys.file_exists filename
    then filename
    else
      begin
	pr2 ("Warning: extending nonstandard filename: "^filename);
	filename ^ ext
      end
  else filename


let filename_of_db (basedir, file) =
  Filename.concat basedir file



let dbe_of_filename file =
  (* raise Invalid_argument if no ext, so safe to use later the unsafe
   * fileprefix and filesuffix functions.
   *)
  ignore(Filename.chop_extension file);
  Filename.dirname file,
  Filename.basename file +> fileprefix,
  Filename.basename file +> filesuffix

let filename_of_dbe (dir, base, ext) =
  Filename.concat dir (base ^ "." ^ ext)


let dbe_of_filename_safe file =
  try Left (dbe_of_filename file)
  with Invalid_argument _ ->
    Right (Filename.dirname file, Filename.basename file)

let normalize_path file =
  let (dir, filename) = Filename.dirname file, Filename.basename file in
  let xs = split "/" dir in
  let rec aux acc = function
    | [] -> List.rev acc
    | x::xs ->
        (match x with
        | "." -> aux acc xs
        | ".." -> aux (List.tl acc) xs
        | x -> aux (x::acc) xs
        )
  in
  let xs' = aux [] xs in
  Filename.concat (String.concat "/" xs') filename


let is_relative s = Filename.is_relative s

let rec join_path dir path =
  match path with
    [] -> assert false
  | hd :: tl ->
     if hd = Filename.current_dir_name then
       join_path dir tl
     else if hd = Filename.parent_dir_name then
       join_path (Filename.dirname dir) tl
     else
       List.fold_left Filename.concat dir path

let rec path_of_filename accu filename =
  let accu = Filename.basename filename :: accu in
  let dirname = Filename.dirname filename in
  if dirname = filename then
    accu
  else
    path_of_filename accu dirname

let path_of_filename filename = path_of_filename [] filename

let join_filename dir filename =
  if Filename.is_relative filename then
    join_path dir (path_of_filename filename)
  else
    filename

let rec resolve_symlink filename =
  match
    try Some (Unix.readlink filename)
    with _ -> None
  with
    Some realpath ->
    let dirname = Filename.dirname filename in
    resolve_symlink (join_filename dirname realpath)
  | None -> filename

(*****************************************************************************)
(* i18n *)
(*****************************************************************************)
type langage =
  | English
  | Francais
  | Deutsch

(* gettext ? *)


(*****************************************************************************)
(* Dates *)
(*****************************************************************************)

(* maybe I should use ocamlcalendar, but I don't like all those functors ... *)

type month =
  | Jan  | Feb  | Mar  | Apr  | May  | Jun
  | Jul  | Aug  | Sep  | Oct  | Nov  | Dec
type year = Year of int
type day = Day of int
type wday = Sunday | Monday | Tuesday | Wednesday | Thursday | Friday | Saturday

type date_dmy = DMY of day * month * year

type hour = Hour of int
type minute = Min of int
type second = Sec of int

type time_hms = HMS of hour * minute * second

type full_date = date_dmy * time_hms


(* intervalle *)
type days = Days of int

type time_dmy = TimeDMY of day * month * year

type float_time = float

(* ---------------------------------------------------------------------- *)

let month_info = [
  1  , Jan, "Jan", "January", 31;
  2  , Feb, "Feb", "February", 28;
  3  , Mar, "Mar", "March", 31;
  4  , Apr, "Apr", "April", 30;
  5  , May, "May", "May", 31;
  6  , Jun, "Jun", "June", 30;
  7  , Jul, "Jul", "July", 31;
  8  , Aug, "Aug", "August", 31;
  9  , Sep, "Sep", "September", 30;
  10 , Oct, "Oct", "October", 31;
  11 , Nov, "Nov", "November", 30;
  12 , Dec, "Dec", "December", 31;
]

let week_day_info = [
  0 , Sunday    , "Sun" , "Dim" , "Sunday";
  1 , Monday    , "Mon" , "Lun" , "Monday";
  2 , Tuesday   , "Tue" , "Mar" , "Tuesday";
  3 , Wednesday , "Wed" , "Mer" , "Wednesday";
  4 , Thursday  , "Thu" ,"Jeu"  ,"Thursday";
  5 , Friday    , "Fri" , "Ven" , "Friday";
  6 , Saturday  , "Sat" ,"Sam"  , "Saturday";
]

let i_to_month_h =
  month_info +> List.map (fun (i,month,monthstr,mlong,days) -> i, month)
let s_to_month_h =
  month_info +> List.map (fun (i,month,monthstr,mlong,days) -> monthstr, month)
let slong_to_month_h =
  month_info +> List.map (fun (i,month,monthstr,mlong,days) -> mlong, month)
let month_to_s_h =
  month_info +> List.map (fun (i,month,monthstr,mlong,days) -> month, monthstr)
let month_to_i_h =
  month_info +> List.map (fun (i,month,monthstr,mlong,days) -> month, i)

let i_to_wday_h =
  week_day_info +> List.map (fun (i,day,dayen,dayfr,daylong) -> i, day)
let wday_to_en_h =
  week_day_info +> List.map (fun (i,day,dayen,dayfr,daylong) -> day, dayen)
let wday_to_fr_h =
  week_day_info +> List.map (fun (i,day,dayen,dayfr,daylong) -> day, dayfr)

let month_of_string s =
  List.assoc s s_to_month_h

let string_of_month s =
  List.assoc s month_to_s_h

let month_of_int i =
  List.assoc i i_to_month_h

let int_of_month m =
  List.assoc m month_to_i_h


let wday_of_int i =
  List.assoc i i_to_wday_h

let string_en_of_wday wday =
  List.assoc wday wday_to_en_h
let string_fr_of_wday wday =
  List.assoc wday wday_to_fr_h

(* ---------------------------------------------------------------------- *)

let wday_str_of_int ~langage i =
  let wday = wday_of_int i in
  match langage with
  | English -> string_en_of_wday wday
  | Francais -> string_fr_of_wday wday
  | Deutsch -> raise Todo



let string_of_unix_time ?(langage=English) tm =
  let y = tm.Unix.tm_year + 1900 in
  let mon = string_of_month (month_of_int (tm.Unix.tm_mon + 1)) in
  let d = tm.Unix.tm_mday in
  let h = tm.Unix.tm_hour in
  let min = tm.Unix.tm_min in
  let s = tm.Unix.tm_sec in

  let wday = wday_str_of_int ~langage tm.Unix.tm_wday in

  spf "%02d/%3s/%04d (%s) %02d:%02d:%02d" d mon y wday h min s

(* ex: 21/Jul/2008 (Lun) 21:25:12 *)
let unix_time_of_string s =
  if s =~
    ("\\([0-9][0-9]\\)/\\(...\\)/\\([0-9][0-9][0-9][0-9]\\) " ^
     "\\(.*\\) \\([0-9][0-9]\\):\\([0-9][0-9]\\):\\([0-9][0-9]\\)")
  then
    let (sday, smonth, syear, _sday, shour, smin, ssec) = matched7 s in

    let y = int_of_string syear - 1900 in
    let mon =
      smonth +> month_of_string +> int_of_month +> (fun i -> i -1)
    in

    let tm = Unix.localtime (Unix.time ()) in
    { tm with
      Unix.tm_year = y;
      Unix.tm_mon = mon;
      Unix.tm_mday = int_of_string sday;
      Unix.tm_hour = int_of_string shour;
      Unix.tm_min = int_of_string smin;
      Unix.tm_sec = int_of_string ssec;
    }
  else failwith ("unix_time_of_string: " ^ s)

(* ---------------------------------------------------------------------- *)

(* (modified) copy paste from ocamlcalendar/src/date.ml *)
let days_month =
  [| 0;    31; 59; 90; 120; 151; 181; 212; 243; 273; 304; 334(*; 365*) |]


let rough_days_since_jesus (DMY (Day nday, month, Year year)) =
  let n =
    nday +
      (days_month.(int_of_month month -1)) +
      year * 365
  in
  Days n



let is_more_recent d1 d2 =
  let (Days n1) = rough_days_since_jesus d1 in
  let (Days n2) = rough_days_since_jesus d2 in
  (n1 > n2)


let rough_days_between_dates d1 d2 =
  let (Days n1) = rough_days_since_jesus d1 in
  let (Days n2) = rough_days_since_jesus d2 in
  Days (n2 - n1)

let _ = example
  (rough_days_between_dates
      (DMY (Day 7, Jan, Year 1977))
      (DMY (Day 13, Jan, Year 1977)) = Days 6)

(* because of rough days, it is a bit buggy, here it should return 1 *)
(*
let _ = assert_equal
  (rough_days_between_dates
      (DMY (Day 29, Feb, Year 1977))
      (DMY (Day 1, Mar , Year 1977)))
  (Days 1)
*)


(* from julia, in gitsort.ml *)

(*
let antimonths =
  [(1,31);(2,28);(3,31);(4,30);(5,31); (6,6);(7,7);(8,31);(9,30);(10,31);
    (11,30);(12,31);(0,31)]

let normalize (year,month,day,hour,minute,second) =
  if hour < 0
  then
    let (day,hour) = (day - 1,hour + 24) in
    if day = 0
    then
      let month = month - 1 in
      let day = List.assoc month antimonths in
      let day =
	if month = 2 && year / 4 * 4 = year && not (year / 100 * 100 = year)
	then 29
	else day in
      if month = 0
      then (year-1,12,day,hour,minute,second)
      else (year,month,day,hour,minute,second)
    else (year,month,day,hour,minute,second)
  else (year,month,day,hour,minute,second)

*)


(* ---------------------------------------------------------------------- *)

let this_year() =
  let time = Unix.gmtime (Unix.time()) in
  time.Unix.tm_year + 1900

(*****************************************************************************)
(* Lines/words/strings *)
(*****************************************************************************)

(* now in prelude:
 * let (list_of_string: string -> char list) = fun s ->
 * (enum 0 ((String.length s) - 1) +> List.map (String.get s))
 *)

let _ = example (list_of_string "abcd" = ['a';'b';'c';'d'])

(*
let rec (list_of_stream: ('a Stream.t) -> 'a list) =
parser
  | [< 'c ; stream >]  -> c :: list_of_stream stream
  | [<>]               -> []

let (list_of_string: string -> char list) =
  Stream.of_string $ list_of_stream
*)

(* now in prelude:
 * let (lines: string -> string list) = fun s -> ...
 *)

let (lines_with_nl: string -> string list) = fun s ->
  let rec lines_aux = function
    | [] -> []
    | [x] -> if x = "" then [] else [x ^ "\n"] (* old: [x] *)
    | x::xs ->
        let e = x ^ "\n" in
        e::lines_aux xs
  in
  (Str.split_delim (Str.regexp "\n") s) +> lines_aux

(* in fact better make it return always complete lines, simplify *)
(*  Str.split, but lines "\n1\n2\n" don't return the \n and forget the first \n => split_delim better than split *)
(* +> List.map (fun s -> s ^ "\n") but add an \n even at the end => lines_aux *)
(* old: slow
  let chars = list_of_string s in
  chars +> List.fold_left (fun (acc, lines) char ->
    let newacc = acc ^ (String.make 1 char) in
    if char = '\n'
    then ("", newacc::lines)
    else (newacc, lines)
    ) ("", [])
       +> (fun (s, lines) -> List.rev (s::lines))
*)

(*  CHECK: unlines (lines x) = x *)
let (unlines: string list -> string) = fun s ->
  (String.concat "\n" s) ^ "\n"
let (words: string -> string list)   = fun s ->
  Str.split (Str.regexp "[ \t()\";]+") s
let (unwords: string list -> string) = fun s ->
  String.concat "" s

let (split_space: string -> string list)   = fun s ->
  Str.split (Str.regexp "[ \t\n]+") s


(* todo opti ? *)
let nblines s =
  lines s +> List.length
let _ = example (nblines "" = 0)
let _ = example (nblines "toto" = 1)
let _ = example (nblines "toto\n" = 1)
let _ = example (nblines "toto\ntata" = 2)
let _ = example (nblines "toto\ntata\n" = 2)

(*****************************************************************************)
(* Process/Files *)
(*****************************************************************************)
let cat_orig file =
  let chan = open_in file in
  let rec cat_orig_aux ()  =
    try
      (* cannot do input_line chan::aux() cos ocaml eval from right to left ! *)
      let l = input_line chan in
      l :: cat_orig_aux ()
    with End_of_file -> [] in
  cat_orig_aux()

(* tail recursive efficient version *)
let cat file =
  let chan = open_in file in
  let rec cat_aux acc ()  =
      (* cannot do input_line chan::aux() cos ocaml eval from right to left ! *)
    let (b, l) = try (true, input_line chan) with End_of_file -> (false, "") in
    if b
    then cat_aux (l::acc) ()
    else acc
  in
  cat_aux [] () +> List.rev +> (fun x -> close_in chan; x)

let cat_array file =
  (""::cat file) +> Array.of_list


(* could do a print_string but printf don't like print_string *)
let echo s = Printf.printf "%s" s; flush stdout; s

(* now in prelude:
 * let command2 s = ignore(Sys.command s)
 *)

let process_output_to_list2 = fun command ->
  let chan = Unix.open_process_in command in
  let res = ref ([] : string list) in
  let rec process_otl_aux () =
    let e = input_line chan in
    res := e::!res;
    process_otl_aux() in
  try process_otl_aux ()
  with End_of_file ->
    let stat = Unix.close_process_in chan in (List.rev !res,stat)
let cmd_to_list command =
  let (l,_) = process_output_to_list2 command in l
let process_output_to_list = cmd_to_list
let cmd_to_list_and_status = process_output_to_list2

let opt_to_list = function
    None   -> []
  | Some e -> [e]
let opt_get = function
    None   -> failwith "option is None"
  | Some e -> e
let file_to_stdout file =
  let i = open_in file in
  let rec loop _ =
    Printf.printf "%s\n" (input_line i); loop() in
  try loop() with End_of_file -> close_in i

let file_to_stderr file =
  let i = open_in file in
  let rec loop _ =
    Printf.eprintf "%s\n" (input_line i); loop() in
  try loop() with End_of_file -> close_in i


(* now in prelude:
 * let command2 s = ignore(Sys.command s)
 *)


let _batch_mode = ref false
let command2_y_or_no cmd =
  if !_batch_mode then begin command2 cmd; true end
  else begin

    pr2 (cmd ^ " [y/n] ?");
    match read_line () with
    | "y" | "yes" | "Y" -> command2 cmd; true
    | "n" | "no"  | "N" -> false
    | _ -> failwith "answer by yes or no"
  end

let command2_y_or_no_exit_if_no cmd =
  let res = command2_y_or_no cmd in
  if res
  then ()
  else raise (UnixExit (1))




let mkdir ?(mode=0o770) file =
  Unix.mkdir file mode

let write_file ~file s =
  let chan = open_out file in
  (output_string chan s; close_out chan)

let filesize file =
  (Unix.stat file).Unix.st_size

let filemtime file =
  (Unix.stat file).Unix.st_mtime

let lfile_exists filename =
  try
    (match (Unix.lstat filename).Unix.st_kind with
    | (Unix.S_REG | Unix.S_LNK) -> true
    | _ -> false
    )
  with
    Unix.Unix_error (Unix.ENOENT, _, _) -> false
  | Unix.Unix_error (Unix.ENOTDIR, _, _) -> false
  | Unix.Unix_error (error, _, fl) ->
      failwith
	(Printf.sprintf "unexpected error %s for file %s"
	   (Unix.error_message error) fl)

let is_directory file =
  (Unix.stat file).Unix.st_kind = Unix.S_DIR


let (readdir_to_kind_list: string -> Unix.file_kind -> string list) =
 fun path kind ->
  Sys.readdir path
  +> Array.to_list
  +> List.filter (fun s ->
    try
      let stat = Unix.lstat (path ^ "/" ^  s) in
      stat.Unix.st_kind = kind
    with e ->
      pr2 ("EXN pb stating file: " ^ s);
      false
    )

let (readdir_to_dir_list: string -> string list) = fun path ->
  readdir_to_kind_list path Unix.S_DIR

let (readdir_to_file_list: string -> string list) = fun path ->
  readdir_to_kind_list path Unix.S_REG

let (readdir_to_link_list: string -> string list) = fun path ->
  readdir_to_kind_list path Unix.S_LNK


let (readdir_to_dir_size_list: string -> (string * int) list) = fun path ->
  Sys.readdir path
  +> Array.to_list
  +> map_filter (fun s ->
    let stat = Unix.lstat (path ^ "/" ^  s) in
    if stat.Unix.st_kind = Unix.S_DIR
    then Some (s, stat.Unix.st_size)
    else None
    )

(* could be in control section too *)

(* Why a use_cache argument ? because sometimes want disable it but don't
 * want put the cache_computation funcall in comment, so just easier to
 * pass this extra option.
 *)
let cache_computation2 ?(verbose=false) ?(use_cache=true) file ext_cache f =
  if not use_cache
  then f ()
  else begin
    if not (Sys.file_exists file)
    then failwith ("can't find: "  ^ file);
    let file_cache = (file ^ ext_cache) in
    if Sys.file_exists file_cache &&
      filemtime file_cache >= filemtime file
    then begin
      if verbose then pr2 ("using cache: " ^ file_cache);
      get_value file_cache
    end
    else begin
      let res = f () in
      write_value res file_cache;
      res
    end
  end
let cache_computation ?verbose ?use_cache a b c =
  profile_code "Common.cache_computation" (fun () ->
    cache_computation2 ?verbose ?use_cache a b c)


let cache_computation_robust2
 dest_dir file ext_cache
 (need_no_changed_files, need_no_changed_variables) ext_depend
 f =
  (if not (Sys.file_exists file)
  then failwith ("can't find: "  ^ file));

  let (file_cache,dependencies_cache) =
    let file_cache = (file ^ ext_cache) in
    let dependencies_cache = (file ^ ext_depend) in
    match dest_dir with
      None -> (file_cache, dependencies_cache)
    | Some dir ->
	let file_cache =
	  Filename.concat dir
	    (if String.get file_cache 0 = '/'
	    then String.sub file_cache 1 ((String.length file_cache) - 1)
	    else file_cache) in
	let dependencies_cache =
	  Filename.concat dir
	    (if String.get dependencies_cache 0 = '/'
	    then
	      String.sub dependencies_cache 1
		((String.length dependencies_cache) - 1)
	    else dependencies_cache) in
	let _ = Sys.command
	    (Printf.sprintf "mkdir -p %s" (Filename.dirname file_cache)) in
	(file_cache,dependencies_cache) in

  let dependencies =
    (* could do md5sum too *)
    ((file::need_no_changed_files) +> List.map (fun f -> f, filemtime f),
     need_no_changed_variables)
  in

  if Sys.file_exists dependencies_cache &&
     get_value dependencies_cache = dependencies
  then
    (*begin
    pr2 ("cache computation reuse " ^ file);*)
    get_value file_cache
    (*end*)
  else begin
    (*pr2 ("cache computation recompute " ^ file);*)
    let res = f () in
    write_value dependencies dependencies_cache;
    write_value res file_cache;
    res
  end

let cache_computation_robust a b c d e =
  profile_code "Common.cache_computation_robust" (fun () ->
    cache_computation_robust2 None a b c d e)

let cache_computation_robust_in_dir a b c d e f =
  profile_code "Common.cache_computation_robust" (fun () ->
    cache_computation_robust2 a b c d e f)




(* don't forget that cmd_to_list call bash and so pattern may contain
 * '*' symbols that will be expanded, so can do  glob "*.c"
 *)
let glob pattern =
  cmd_to_list ("ls -1 " ^ pattern)


(* update: have added the -type f, so normally need less the sanity_check_xxx
 * function below *)
let files_of_dir_or_files ext xs =
  xs +> List.map (fun x ->
    if is_directory x
    then cmd_to_list ("find " ^ x  ^" -noleaf -type f -name \"*." ^ext^"\"")
    else [x]
  ) +> List.concat


let files_of_dir_or_files_no_vcs ext xs =
  xs +> List.map (fun x ->
    if is_directory x
    then
      cmd_to_list
        ("find " ^ x  ^" -noleaf -type f -name \"*." ^ext^"\"" ^
            "| grep -v /.hg/ |grep -v /CVS/ | grep -v /.git/ |grep -v /_darcs/"
        )
    else [x]
  ) +> List.concat


(* emacs/lisp inspiration (eric cooper and yaron minsky use that too) *)
let (with_open_outfile: filename -> (((string -> unit) * out_channel) -> 'a) -> 'a) =
 fun file f ->
  let chan = open_out file in
  let pr s = output_string chan s in
  unwind_protect (fun () ->
    let res = f (pr, chan) in
    close_out chan;
    res)
    (fun e -> close_out chan)

let (with_open_infile: filename -> ((in_channel) -> 'a) -> 'a) = fun file f ->
  let chan = open_in file in
  unwind_protect (fun () ->
    let res = f chan in
    close_in chan;
    res)
    (fun e -> close_in chan)


let (with_open_outfile_append: filename -> (((string -> unit) * out_channel) -> 'a) -> 'a) =
 fun file f ->
  let chan = open_out_gen [Open_creat;Open_append] 0o666 file in
  let pr s = output_string chan s in
  unwind_protect (fun () ->
    let res = f (pr, chan) in
    close_out chan;
    res)
    (fun e -> close_out chan)


(* now in prelude:
 * exception Timeout
 *)

(* it seems that the toplevel block such signals, even with this explicit
 *  command :(
 *  let _ = Unix.sigprocmask Unix.SIG_UNBLOCK [Sys.sigalrm]
 *)

(* could be in Control section *)

(* subtil: have to make sure that timeout is not intercepted before here, so
 * avoid exn handle such as try (...) with _ -> cos timeout will not bubble up
 * enough. In such case, add a case before such as
 * with Timeout -> raise Timeout | _ -> ...
 *
 * question: can we have a signal and so exn when in a exn handler ?
 *)

let interval_timer = ref (
  try
    ignore(Unix.getitimer Unix.ITIMER_VIRTUAL);
    true
  with Unix.Unix_error(_, _, _) -> false)

let timeout_function s timeoutval = fun f ->
  try
    if !interval_timer
    then
      begin
        Sys.set_signal Sys.sigvtalrm
	  (Sys.Signal_handle (fun _ -> raise Timeout));
	ignore
	  (Unix.setitimer Unix.ITIMER_VIRTUAL
             {Unix.it_interval=float_of_int timeoutval;
               Unix.it_value =float_of_int timeoutval});
	let x = f() in
	ignore(Unix.alarm 0);
	x
      end
    else
      begin
	Sys.set_signal Sys.sigalrm
	  (Sys.Signal_handle (fun _ -> raise Timeout ));
	ignore(Unix.alarm timeoutval);
	let x = f() in
	ignore(Unix.alarm 0);
	x
      end
  with Timeout ->
    begin
      (if !print_to_stderr
      then log (Printf.sprintf "timeout (we abort)")
      else log (Printf.sprintf "timeout (we abort): %s" s));
      (*pr2 (List.hd(cmd_to_list "free -m | grep Mem"));*)
      raise Timeout;
    end
  | e ->
     (* subtil: important to disable the alarm before relaunching the exn,
      * otherwise the alarm is still running.
      *
      * robust?: and if alarm launched after the log (...) ?
      * Maybe signals are disabled when process an exception handler ?
      *)
      begin
        ignore(Unix.alarm 0);
        (* log ("exn while in transaction (we abort too, even if ...) = " ^
           Printexc.to_string e);
        *)
        log "exn while in timeout_function";
        raise e
      end

let timeout_function_opt s timeoutvalopt f =
  match timeoutvalopt with
  | None -> f()
  | Some x -> timeout_function s x f


(* removes only if the file does not exists *)
let remove_file path =
  if Sys.file_exists path
  then Sys.remove path
  else ()

(* creation of tmp files, a la gcc *)

let _temp_files_created = ref ([] : filename list)

let temp_files = ref "/tmp"

(* ex: new_temp_file "cocci" ".c" will give "/tmp/cocci-3252-434465.c" *)
let new_temp_file prefix suffix =
  let processid = string_of_int (Unix.getpid ()) in
  let tmp_file =
    Filename.temp_file ~temp_dir:(!temp_files)
      (prefix ^ "-" ^ processid ^ "-") suffix in
  push2 tmp_file _temp_files_created;
  tmp_file


let save_tmp_files = ref false
let erase_temp_files () =
  if not !save_tmp_files then begin
    !_temp_files_created +> List.iter (fun s ->
      (* pr2 ("erasing: " ^ s); *)
      remove_file s
    );
    _temp_files_created := []
  end


(* now in prelude: exception UnixExit of int *)
let exn_to_real_unixexit f =
  try f()
  with UnixExit x -> exit x


(*****************************************************************************)
(* List *)
(*****************************************************************************)

let rec find_map f = function
  | [] -> None
  | v::l ->
      match f v with
      | None -> find_map f l
      | res -> res

(* pixel *)
let uncons l = (List.hd l, List.tl l)

let push l v =
  l := v :: !l

let rec zip xs ys =
  match (xs,ys) with
  | ([],[]) -> []
  | ([],_) -> failwith "zip: not same length"
  | (_,[]) -> failwith "zip: not same length"
  | (x::xs,y::ys) -> (x,y)::zip xs ys

let rec combine4 : 'a list -> 'b list -> 'c list -> 'd list ->
                      ('a * 'b * 'c * 'd) list
  = fun a b c d -> match (a,b,c,d) with
  | ([],[],[],[])             -> []
  | (w::ws,x::xs,y::ys,z::zs) -> (w,x,y,z)::combine4 ws xs ys zs
  | ___else___                -> invalid_arg "combine4: not same length"

let rec zip_safe xs ys =
  match (xs,ys) with
  | ([],_) -> []
  | (_,[]) -> []
  | (x::xs,y::ys) -> (x,y)::zip_safe xs ys

let unzip zs =
  List.fold_right (fun e (xs, ys)    ->
    (fst e::xs), (snd e::ys)) zs ([],[])


(* now in prelude
 * let rec take n xs =
 * match (n,xs) with
 * | (0,_) -> []
 * | (_,[]) -> failwith "take: not enough"
 * | (n,x::xs) -> x::take (n-1) xs
 *)

let rec take_safe n xs =
  match (n,xs) with
  | (0,_) -> []
  | (_,[]) -> []
  | (n,x::xs) -> x::take_safe (n-1) xs

let rec take_until p = function
  | [] -> []
  | x::xs -> if p x then [] else x::(take_until p xs)

let take_while p = take_until (p $ not)


(* now in prelude: let rec drop n xs = ... *)
let _ = example (drop 3 [1;2;3;4] = [4])

let rec drop_while p = function
  | [] -> []
  | x::xs -> if p x then drop_while p xs else x::xs


let drop_until p xs =
  drop_while (fun x -> not (p x)) xs
let _ = example (drop_until (fun x -> x = 3) [1;2;3;4;5] = [3;4;5])


let span p xs = (take_while p xs, drop_while p xs)


let rec (span: ('a -> bool) -> 'a list -> 'a list * 'a list) =
 fun p -> function
  | []    -> ([], [])
  | x::xs ->
      if p x then
	let (l1, l2) = span p xs in
	(x::l1, l2)
      else ([], x::xs)
let _ = example ((span (fun x -> x <= 3) [1;2;3;4;1;2] = ([1;2;3],[4;1;2])))

let rec groupBy eq l =
  match l with
  | [] -> []
  | x::xs ->
      let (xs1,xs2) = List.partition (fun x' -> eq x x') xs in
      (x::xs1)::(groupBy eq xs2)

let rec group_by_mapped_key fkey l =
  match l with
  | [] -> []
  | x::xs ->
      let k = fkey x in
      let (xs1,xs2) = List.partition (fun x' -> let k2 = fkey x' in k=k2) xs
      in
      (k, (x::xs1))::(group_by_mapped_key fkey xs2)




let (exclude_but_keep_attached: ('a -> bool) -> 'a list -> ('a * 'a list) list)=
 fun f xs ->
   let rec aux_filter acc ans = function
   | [] -> (* drop what was accumulated because nothing to attach to *)
       List.rev ans
   | x::xs ->
       if f x
       then aux_filter (x::acc) ans xs
       else aux_filter [] ((x, List.rev acc)::ans) xs
   in
   aux_filter [] [] xs
let _ = example
  (exclude_but_keep_attached (fun x -> x = 3) [3;3;1;3;2;3;3;3] =
      [(1,[3;3]);(2,[3])])

let group_by_post: ('a -> bool) -> 'a list -> ('a list * 'a) list * 'a list =
 fun f xs ->
   let rec aux_filter grouped_acc acc = function
   | [] ->
       List.rev grouped_acc, List.rev acc
   | x::xs ->
       if f x
       then
         aux_filter ((List.rev acc,x)::grouped_acc) [] xs
       else
         aux_filter grouped_acc (x::acc) xs
   in
   aux_filter [] [] xs

let _ = example
  (group_by_post (fun x -> x = 3) [1;1;3;2;3;4;5;3;6;6;6] =
      ([([1;1],3);([2],3);[4;5],3], [6;6;6]))

let (group_by_pre: ('a -> bool) -> 'a list -> 'a list * ('a * 'a list) list)=
  fun f xs ->
    let xs' = List.rev xs in
    let (ys, unclassified) = group_by_post f xs' in
    List.rev unclassified,
    ys +> List.rev +> List.map (fun (xs, x) -> x, List.rev xs )

let _ = example
  (group_by_pre (fun x -> x = 3) [1;1;3;2;3;4;5;3;6;6;6] =
      ([1;1], [(3,[2]); (3,[4;5]); (3,[6;6;6])]))


let split_when: ('a -> bool) -> 'a list -> 'a list * 'a * 'a list =
 fun p l ->
  let rec loop acc = function
  | []    -> raise Not_found
  | x::xs ->
      if p x then
        List.rev acc, x, xs
      else loop (x :: acc) xs in
  loop [] l
let _ = example (split_when (fun x -> x = 3)
                    [1;2;3;4;1;2] = ([1;2],3,[4;1;2]))


(* not so easy to come up with ... used in aComment for split_paragraph *)
let rec split_gen_when_aux f acc xs =
  match xs with
  | [] ->
      if acc=[]
      then []
      else [List.rev acc]
  | (x::xs) ->
      (match f (x::xs) with
      | None ->
          split_gen_when_aux f (x::acc) xs
      | Some (rest) ->
          let before = List.rev acc in
          if before=[]
          then split_gen_when_aux f [] rest
          else before::split_gen_when_aux f [] rest
      )
(* could avoid introduce extra aux function by using ?(acc = []) *)
let split_gen_when f xs =
  split_gen_when_aux f [] xs



(* generate exception (Failure "tl") if there is no element satisfying p *)
let rec (skip_until: ('a list -> bool) -> 'a list -> 'a list) = fun p xs ->
  if p xs then xs else skip_until p (List.tl xs)
let _ = example
  (skip_until (function 1::2::xs -> true | _ -> false)
      [1;3;4;1;2;4;5] = [1;2;4;5])

let rec skipfirst e = function
  | [] -> []
  | e'::l when e = e' -> skipfirst e l
  | l -> l


(* now in prelude:
 * let rec enum x n = ...
 *)


let index_list xs =
  if xs=[] then [] (* enum 0 (-1) generate an exception *)
  else zip xs (enum 0 ((List.length xs) -1))

let index_list_1 xs =
  xs +> index_list +> List.map (fun (x,i) -> x, i+1)

let or_list  = List.fold_left (||) false
let and_list = List.fold_left (&&) true

let cons x xs = x::xs

let head_middle_tail xs =
  match xs with
  | x::y::xs ->
      let head = x in
      let reversed = List.rev (y::xs) in
      let tail = List.hd reversed in
      let middle = List.rev (List.tl reversed) in
      head, middle, tail
  | _ -> failwith "head_middle_tail, too small list"

let _ = assert_equal (head_middle_tail [1;2;3]) (1, [2], 3)
let _ = assert_equal (head_middle_tail [1;3]) (1, [], 3)

(* let (++) l1 l2 = List.fold_right (fun x acc -> x::acc) l1 l2 *)

let remove x xs =
  let newxs = List.filter (fun y -> y <> x) xs in
  assert (List.length newxs = List.length xs - 1);
  newxs


let exclude p xs =
  List.filter (fun x -> not (p x)) xs

(* now in prelude
*)

let fold_k f lastk acc xs =
  let rec fold_k_aux acc = function
    | [] -> lastk acc
    | x::xs ->
        f acc x (fun acc -> fold_k_aux acc xs)
  in
  fold_k_aux acc xs


let rec list_init = function
  | []       -> raise Not_found
  | [x]      -> []
  | x::y::xs -> x::(list_init (y::xs))

let rec list_last = function
  | [] -> raise Not_found
  | [x] -> x
  | x::y::xs -> list_last (y::xs)

(* pixel *)
(* now in prelude
 *   let last_n n l = List.rev (take n (List.rev l))
 *   let last l = List.hd (last_n 1 l)
 *)

let rec join_gen a = function
  | [] -> []
  | [x] -> [x]
  | x::xs -> x::a::(join_gen a xs)


(* todo: foldl, foldr (a more consistent foldr) *)

(* pixel *)
let filter_index f l =
  let rec filt i = function
    | [] -> []
    | e::l -> if f i e then e :: filt (i+1) l else filt (i+1) l
  in
  filt 0 l

(* pixel *)
let do_withenv doit f env l =
  let r_env = ref env in
  let l' = doit (fun e ->
    let e', env' = f !r_env e in
    r_env := env' ; e'
  ) l in
  l', !r_env

(* now in prelude:
 * let fold_left_with_index f acc = ...
 *)

let map_withenv      f env e = do_withenv List.map f env e

let rec collect_accu f accu = function
  | [] -> accu
  | e::l -> collect_accu f (List.rev_append (f e) accu) l

let collect f l = List.rev (collect_accu f [] l)

(* end pixel *)

let rec removelast = function
  | [] -> failwith "removelast"
  | [_] -> []
  | e::l -> e :: removelast l

let remove x = List.filter (fun y -> y != x)

let rec inits = function
  | [] -> [[]]
  | e::l -> [] :: List.map (fun l -> e::l) (inits l)

let rec tails = function
  | [] -> [[]]
  | (_::xs) as xxs -> xxs :: tails xs


let reverse = List.rev
let rev = List.rev

let nth = List.nth
let fold_left = List.fold_left
let rev_map = List.rev_map

(* pixel *)
let rec fold_right1 f = function
  | [] -> failwith "fold_right1"
  | [e] -> e
  | e::l -> f e (fold_right1 f l)

let maximum l = foldl1 max l
let minimum l = foldl1 min l

(* do a map tail recursive, and result is reversed, it is a tail recursive map => efficient *)
let map_eff_rev = fun f l ->
  let rec map_eff_aux acc =
    function
      |	[]    -> acc
      |	x::xs -> map_eff_aux ((f x)::acc) xs
  in
  map_eff_aux [] l

let acc_map f l =
  let rec loop acc = function
    [] -> List.rev acc
  | x::xs -> loop ((f x)::acc) xs in
  loop [] l


let rec (generate: int -> 'a -> 'a list) = fun i el ->
  if i = 0 then []
  else el::(generate (i-1) el)

let rec uniq = function
  | [] -> []
  | e::l -> if List.mem e l then uniq l else e :: uniq l

let has_no_duplicate xs =
  List.length xs = List.length (uniq xs)
let is_set_as_list = has_no_duplicate


let rec get_duplicates xs =
  match xs with
  | [] -> []
  | x::xs ->
      if List.mem x xs
      then x::get_duplicates xs (* todo? could x from xs to avoid double dups?*)
      else get_duplicates xs

let rec all_assoc e = function
  | [] -> []
  | (e',v) :: l when e=e' -> v :: all_assoc e l
  | _ :: l -> all_assoc e l

let rotate list = List.tl list @ [(List.hd list)]

let or_list  = List.fold_left (||) false
let and_list = List.fold_left (&&) true

let rec (return_when: ('a -> 'b option) -> 'a list -> 'b) = fun p -> function
  | [] -> raise Not_found
  | x::xs -> (match p x with None -> return_when p xs | Some b -> b)

let rec splitAt n xs =
  if n = 0 then ([],xs)
  else
    (match xs with
    | []      -> ([],[])
    | (x::xs) -> let (a,b) = splitAt (n-1) xs in (x::a, b)
    )

let pack n xs =
  let rec pack_aux l i = function
    | [] -> failwith "not on a boundary"
    | [x] -> if i = n then [l @ [x]] else failwith "not on a boundary"
    | x::xs ->
        if i = n
        then (l @ [x])::(pack_aux [] 1 xs)
        else pack_aux (l @ [x]) (i+1) xs
  in
  pack_aux [] 1 xs

let min_with f = function
  | [] -> raise Not_found
  | e :: l ->
      let rec min_with_ min_val min_elt = function
	| [] -> min_elt
	| e::l ->
	    let val_ = f e in
	    if val_ < min_val
	    then min_with_ val_ e l
	    else min_with_ min_val min_elt l
      in min_with_ (f e) e l

let grep_with_previous f = function
  | [] -> []
  | e::l ->
      let rec grep_with_previous_ previous = function
	| [] -> []
	| e::l -> if f previous e then e :: grep_with_previous_ e l else grep_with_previous_ previous l
      in e :: grep_with_previous_ e l

let iter_with_previous f = function
  | [] -> ()
  | e::l ->
      let rec iter_with_previous_ previous = function
	| [] -> ()
	| e::l -> f previous e ; iter_with_previous_ e l
      in iter_with_previous_ e l


(* kind of cartesian product of x*x  *)
let rec (get_pair: ('a list) -> (('a * 'a) list)) = function
  | [] -> []
  | x::xs -> (List.map (fun y -> (x,y)) xs) @ (get_pair xs)


(* retourne le rang dans une liste d'un element *)
let rang elem liste =
  let rec rang_rec elem accu = function
    | []   -> raise Not_found
    | a::l -> if a = elem then accu
    else rang_rec elem (accu+1) l in
  rang_rec elem 1 liste

(* retourne vrai si une liste contient des doubles *)
let rec doublon = function
  | []   -> false
  | a::l -> if List.mem a l then true
  else doublon l

let rec (insert_in: 'a -> 'a list -> 'a list list) = fun x -> function
  | []    -> [[x]]
  | y::ys -> (x::y::ys)  :: (List.map (fun xs -> y::xs) (insert_in x ys))
(* insert_in 3 [1;2] = [[3; 1; 2]; [1; 3; 2]; [1; 2; 3]] *)

let rec (permutation: 'a list -> 'a list list) = function
  | [] -> []
  | [x] -> [[x]]
  | x::xs -> List.flatten (List.map (insert_in x) (permutation xs))
(* permutation [1;2;3] =
 * [[1; 2; 3]; [2; 1; 3]; [2; 3; 1]; [1; 3; 2]; [3; 1; 2]; [3; 2; 1]]
 *)


let rec remove_elem_pos pos xs =
  match (pos, xs) with
  | _, [] -> failwith "remove_elem_pos"
  | 0, x::xs -> xs
  | n, x::xs -> x::(remove_elem_pos (n-1) xs)

let rec insert_elem_pos (e, pos) xs =
  match (pos, xs) with
  | 0, xs -> e::xs
  | n, x::xs -> x::(insert_elem_pos (e, (n-1)) xs)
  | n, [] -> failwith "insert_elem_pos"

let uncons_permut xs =
  let indexed = index_list xs in
  indexed +> List.map (fun (x, pos) -> (x, pos),  remove_elem_pos pos xs)
let _ =
  example
    (uncons_permut ['a';'b';'c'] =
     [('a', 0),  ['b';'c'];
      ('b', 1),  ['a';'c'];
      ('c', 2),  ['a';'b']
     ])

let uncons_permut_lazy xs =
  let indexed = index_list xs in
  indexed +> List.map (fun (x, pos) ->
    (x, pos),
    lazy (remove_elem_pos pos xs)
  )




(* pixel *)
let map_flatten f l =
  let rec map_flatten_aux accu = function
    | [] -> accu
    | e :: l -> map_flatten_aux (List.rev (f e) @ accu) l
  in List.rev (map_flatten_aux [] l)


let repeat e n =
    let rec repeat_aux acc = function
      | 0 -> acc
      | n when n < 0 -> failwith "repeat"
      | n -> repeat_aux (e::acc) (n-1) in
    repeat_aux [] n

let rec map2 f = function
  | [] -> []
  | x::xs -> let r = f x in r::map2 f xs

let map3 f l =
  let rec map3_aux acc = function
    | [] -> acc
    | x::xs -> map3_aux (f x::acc) xs in
  map3_aux [] l

(*
let tails2 xs = map rev (inits (rev xs))
let res = tails2 [1;2;3;4]
let res = tails [1;2;3;4]
let id x = x
*)

let pack_sorted same xs =
    let rec pack_s_aux acc xs =
      match (acc,xs) with
      |	((cur,rest),[]) -> cur::rest
      |	((cur,rest), y::ys) ->
	  if same (List.hd cur) y then pack_s_aux (y::cur, rest) ys
	  else pack_s_aux ([y], cur::rest) ys
    in pack_s_aux ([List.hd xs],[]) (List.tl xs) +> List.rev
let test = pack_sorted (=) [1;1;1;2;2;3;4]


let rec keep_best f =
  let rec partition e = function
    | [] -> e, []
    | e' :: l ->
	match f(e,e') with
	| None -> let (e'', l') = partition e l in e'', e' :: l'
	| Some e'' -> partition e'' l
  in function
  | [] -> []
  | e::l ->
      let (e', l') = partition e l in
      e' :: keep_best f l'

let rec sorted_keep_best f = function
  | [] -> []
  | [a] -> [a]
  | a :: b :: l ->
      match f a b with
      |	None -> a :: sorted_keep_best f (b :: l)
      |	Some e -> sorted_keep_best f (e :: l)



let (cartesian_product: 'a list -> 'b list -> ('a * 'b) list) = fun xs ys ->
  xs +> List.map (fun x ->  ys +> List.map (fun y -> (x,y)))
     +> List.flatten

let _ = assert_equal
    (cartesian_product [1;2] ["3";"4";"5"])
    [1,"3";1,"4";1,"5";  2,"3";2,"4";2,"5"]


let rec equal_list f l0 l1 =
  match l0, l1 with
    [], [] -> true
  | h0 :: t0, h1 :: t1 -> f h0 h1 && equal_list f t0 t1
  | [], _ :: _
  | _ :: _, [] -> false


let sort_prof a b =
  profile_code "Common.sort_by_xxx" (fun () -> List.sort a b)

let sort_by_key_highfirst xs =
  sort_prof (fun (k1,v1) (k2,v2) -> compare k2 k1) xs
let sort_by_key_lowfirst xs =
  sort_prof (fun (k1,v1) (k2,v2) -> compare k1 k2) xs

let _ = example (sort_by_key_lowfirst [4, (); 7,()] = [4,(); 7,()])
let _ = example (sort_by_key_highfirst [4,(); 7,()] = [7,(); 4,()])

(*----------------------------------*)

(* sur surEnsemble [p1;p2] [[p1;p2;p3] [p1;p2] ....] -> [[p1;p2;p3] ...      *)
(* mais pas p2;p3                                                            *)
(* (aop) *)
let surEnsemble  liste_el liste_liste_el =
  List.filter
    (function liste_elbis ->
      List.for_all (function el -> List.mem el liste_elbis) liste_el
    ) liste_liste_el;;



(*----------------------------------*)
(* combinaison/product/.... (aop) *)
(* 123 -> 123 12 13 23 1 2 3 *)
let rec realCombinaison = function
  | []  -> []
  | [a] -> [[a]]
  | a::l  ->
      let res  = realCombinaison l in
      let res2 = List.map (function x -> a::x) res in
      res2 @ res @ [[a]]

(* genere toutes les combinaisons possible de paire      *)
(* par example combinaison [1;2;4] -> [1, 2; 1, 4; 2, 4] *)
let rec combinaison = function
  | [] -> []
  | [a] -> []
  | [a;b] -> [(a, b)]
  | a::b::l -> (List.map (function elem -> (a, elem)) (b::l)) @
     (combinaison (b::l))

(*----------------------------------*)

(* list of list(aop) *)
(* insere elem dans la liste de liste (si elem est deja present dans une de  *)
(* ces listes, on ne fait rien                                               *)
let rec insere elem = function
  | []   -> [[elem]]
  | a::l ->
      if (List.mem elem a) then a::l
      else a::(insere elem l)

let rec insereListeContenant lis el = function
  | []   -> [el::lis]
  | a::l ->
      if List.mem el a then
	(List.append lis a)::l
      else a::(insereListeContenant lis el l)

(* fusionne les listes contenant et1 et et2  dans la liste de liste*)
let rec fusionneListeContenant (et1, et2) = function
  | []   -> [[et1; et2]]
  | a::l ->
      (* si les deux sont deja dedans alors rien faire *)
      if List.mem et1 a then
	if List.mem et2 a then a::l
	else
	  insereListeContenant a et2 l
      else if List.mem et2 a then
	insereListeContenant a et1 l
      else a::(fusionneListeContenant (et1, et2) l)

(*****************************************************************************)
(* Arrays *)
(*****************************************************************************)

(* do bound checking ? *)
let array_find_index f a =
  let rec array_find_index_ i =
    if f i then i else array_find_index_ (i+1)
  in
  try array_find_index_ 0 with _ -> raise Not_found

(*****************************************************************************)
(* Matrix *)
(*****************************************************************************)

type 'a matrix = 'a array array

let (make_matrix_init:
        nrow:int -> ncolumn:int -> (int -> int -> 'a) -> 'a matrix) =
 fun ~nrow ~ncolumn f ->
  Array.init nrow (fun i ->
    Array.init ncolumn (fun j ->
      f i j
    )
  )

let nb_rows_matrix m =
  Array.length m

let nb_columns_matrix m =
  assert(Array.length m > 0);
  Array.length m.(0)

let (rows_of_matrix: 'a matrix -> 'a list list) = fun m ->
  Array.to_list m +> List.map Array.to_list

let (columns_of_matrix: 'a matrix -> 'a list list) = fun m ->
  let nbcols = nb_columns_matrix m in
  let nbrows = nb_rows_matrix m in
  (enum 0 (nbcols -1)) +> List.map (fun j ->
    (enum 0 (nbrows -1)) +> List.map (fun i ->
      m.(i).(j)
    ))

let ex_matrix1 =
  [|
    [|0;1;2|];
    [|3;4;5|];
    [|6;7;8|];
  |]
let ex_rows1 =
  [
    [0;1;2];
    [3;4;5];
    [6;7;8];
  ]
let ex_columns1 =
  [
    [0;3;6];
    [1;4;7];
    [2;5;8];
  ]
let _ = example (rows_of_matrix ex_matrix1 = ex_rows1)
let _ = example (columns_of_matrix ex_matrix1 = ex_columns1)


(*****************************************************************************)
(* Fast array *)
(*****************************************************************************)
(*
module B_Array = Bigarray.Array2
*)

(*
open B_Array
open Bigarray
*)

(*****************************************************************************)
(* Set. Have a look too at set*.mli  *)
(*****************************************************************************)
type 'a set = 'a list
  (* with sexp *)

let (empty_set: 'a set) = []
let (insert_set: 'a -> 'a set -> 'a set) = fun x xs ->
  if List.mem x xs
  then (* let _ = print_string "warning insert: already exist" in *)
    xs
  else x::xs

let (single_set: 'a -> 'a set) = fun x -> insert_set x empty_set
let (set: 'a list -> 'a set) = fun xs ->
  xs +> List.fold_left (flip insert_set) empty_set

let (exists_set: ('a -> bool) -> 'a set -> bool) = List.exists
let (forall_set: ('a -> bool) -> 'a set -> bool) = List.for_all
let (filter_set: ('a -> bool) -> 'a set -> 'a set) = List.filter
let (fold_set: ('a -> 'b -> 'a) -> 'a -> 'b set -> 'a) = List.fold_left
let (map_set: ('a -> 'b) -> 'a set -> 'b set) = List.map
let (member_set: 'a -> 'a set -> bool) = List.mem

let find_set = List.find
let sort_set = List.sort
let iter_set = List.iter

let (top_set: 'a set -> 'a) = List.hd

let (inter_set: 'a set -> 'a set -> 'a set) = fun s1 s2 ->
  s1 +> fold_set (fun acc x -> if member_set x s2 then insert_set x acc else acc) empty_set
let (union_set: 'a set -> 'a set -> 'a set) = fun s1 s2 ->
  s2 +> fold_set (fun acc x -> if member_set x s1 then acc else insert_set x acc) s1
let (minus_set: 'a set -> 'a set -> 'a set) = fun s1 s2 ->
  s1 +> filter_set  (fun x -> not (member_set x s2))


let union_all l = List.fold_left union_set [] l

let inter_all = function
    [] -> []
  | x::xs -> List.fold_left inter_set x xs

let (card_set: 'a set -> int) = List.length

let (include_set: 'a set -> 'a set -> bool) = fun s1 s2 ->
  (s1 +> forall_set (fun p -> member_set p s2))

let equal_set s1 s2 = include_set s1 s2 && include_set s2 s1

let (include_set_strict: 'a set -> 'a set -> bool) = fun s1 s2 ->
  (card_set s1 < card_set s2) && (include_set s1 s2)

let ($*$) = inter_set
let ($+$) = union_set
let ($-$) = minus_set
let ($?$) a b = profile_code "$?$" (fun () -> member_set a b)
let ($<$) = include_set_strict
let ($<=$) = include_set
let ($=$) = equal_set

(* as $+$ but do not check for memberness, allow to have set of func *)
let ($@$) = fun a b -> a @ b

let nub l =
  let l = List.sort compare l in
  let rec loop = function
      [] -> []
    | x::((y::_) as xs) when x = y -> loop xs
    | x::xs -> x :: loop xs in
  loop l

(*****************************************************************************)
(* Set as normal list *)
(*****************************************************************************)
(*
let (union: 'a list -> 'a list -> 'a list) = fun l1 l2 ->
  List.fold_left (fun acc x -> if List.mem x l1 then acc else x::acc) l1 l2

let insert_normal x xs = union xs [x]

(* retourne lis1 - lis2 *)
let minus l1 l2 = List.filter    (fun x -> not (List.mem x l2)) l1

let inter l1 l2 = List.fold_left (fun acc x -> if List.mem x l2 then x::acc else acc) [] l1

let union_list =  List.fold_left union []

let uniq lis =
  List.fold_left (function acc -> function el -> union [el] acc) [] lis

(* pixel *)
let rec non_uniq = function
  | [] -> []
  | e::l -> if mem e l then e :: non_uniq l else non_uniq l

let rec inclu lis1 lis2 =
  List.for_all (function el -> List.mem el lis2) lis1

let equivalent lis1 lis2 =
  (inclu lis1 lis2) && (inclu lis2 lis1)

*)


(*****************************************************************************)
(* Set as sorted list *)
(*****************************************************************************)
(* liste trie, cos we need to do intersection, and insertion (it is a set
   cos when introduce has, if we create a new has => must do a recurse_rep
   and another categ can have to this has => must do an union
 *)
(*
let rec insert x = function
  | [] -> [x]
  | y::ys ->
      if x = y then y::ys
      else (if x < y then x::y::ys else y::(insert x ys))

(* same, suppose sorted list *)
let rec intersect x y =
  match(x,y) with
  | [], y -> []
  | x,  [] -> []
  | x::xs, y::ys ->
      if x = y then x::(intersect xs ys)
      else
	(if x < y then intersect xs (y::ys)
	else intersect (x::xs) ys
	)
(* intersect [1;3;7] [2;3;4;7;8];;   *)
*)

(*****************************************************************************)
(* Assoc *)
(*****************************************************************************)
type ('a,'b) assoc  = ('a * 'b) list
  (* with sexp *)


let (assoc_to_function: ('a, 'b) assoc -> ('a -> 'b)) = fun xs ->
  xs +> List.fold_left (fun acc (k, v) ->
    (fun k' ->
      if k = k' then v else acc k'
    )) (fun k -> failwith "no key in this assoc")
(* simpler:
let (assoc_to_function: ('a, 'b) assoc -> ('a -> 'b)) = fun xs ->
  fun k -> List.assoc k xs
*)

let (empty_assoc: ('a, 'b) assoc) = []
let fold_assoc = List.fold_left
let insert_assoc = fun x xs -> x::xs
let map_assoc = List.map
let filter_assoc = List.filter

let assoc = List.assoc
let keys xs = List.map fst xs

let lookup = assoc

(* assert unique key ?*)
let del_assoc key xs = xs +> List.filter (fun (k,v) -> k <> key)

(* todo: pb normally can suppr fun l -> .... l but if do that, then strange type _a
 => assoc_map is strange too => equal don't work
*)
let (assoc_reverse: (('a * 'b) list) -> (('b * 'a) list)) = fun l ->
  List.map (fun(x,y) -> (y,x)) l

let (assoc_map: (('a * 'b) list) -> (('a * 'b) list) -> (('a * 'a) list)) =
 fun l1 l2 ->
  let (l1bis, l2bis) = (assoc_reverse l1, assoc_reverse l2) in
  List.map (fun (x,y) -> (y, List.assoc x l2bis )) l1bis

let rec (lookup_list: 'a -> ('a , 'b) assoc list -> 'b) = fun el -> function
  | [] -> raise Not_found
  | (xs::xxs) -> try List.assoc el xs with Not_found -> lookup_list el xxs

let (lookup_list2: 'a -> ('a , 'b) assoc list -> ('b * int)) = fun el xxs ->
  let rec lookup_l_aux i = function
  | [] -> raise Not_found
  | (xs::xxs) ->
      try let res = List.assoc el xs in (res,i)
      with Not_found -> lookup_l_aux (i+1) xxs
  in lookup_l_aux 0 xxs

let _ = example
  (lookup_list2 "c" [["a",1;"b",2];["a",1;"b",3];["a",1;"c",7]] = (7,2))


let assoc_option  k l =
  optionise (fun () -> List.assoc k l)

let assoc_with_err_msg k l =
  try List.assoc k l
  with Not_found ->
    pr2 (spf "pb assoc_with_err_msg: %s" (Dumper.dump k));
    raise Not_found

(*****************************************************************************)
(* Assoc int -> xxx with binary tree.  Have a look too at Mapb.mli *)
(*****************************************************************************)

(* ex: type robot_list = robot_info IntMap.t *)
module IntMap = Map.Make
    (struct
      type t = int
      let compare (x : int) (y : int) = Stdcompat.Stdlib.compare x y
    end)

module IntIntMap = Map.Make
    (struct
      type t = int * int
      let compare ((x1, y1) : int * int) ((x2, y2) : int * int) =
	let cmp_x = Stdcompat.Stdlib.compare x1 x2 in
	if cmp_x <> 0 then
	  cmp_x
	else
	  Stdcompat.Stdlib.compare y1 y2
end)

(*****************************************************************************)
(* Hash *)
(*****************************************************************************)

let hash_to_list h =
  Hashtbl.fold (fun k v acc -> (k,v)::acc) h []
  +> List.sort compare

let hash_of_list xs =
  let h = Hashtbl.create 101 in
  begin
    xs +> List.iter (fun (k, v) -> Hashtbl.add h k v);
    h
  end

let hashadd tbl k v =
  let cell =
    try Hashtbl.find tbl k
    with Not_found ->
      let cell = ref [] in
      Hashtbl.add tbl k cell;
      cell in
  if not (List.mem v !cell) then cell := v :: !cell

let hashadd_notest tbl k v =
  try
    let cur = Hashtbl.find tbl k in
    Hashtbl.replace tbl k (v::cur)
  with Not_found -> Hashtbl.add tbl k [v]

let _  =
  let h = Hashtbl.create 101 in
  Hashtbl.add h "toto" 1;
  Hashtbl.add h "toto" 1;
  assert(hash_to_list h = ["toto",1; "toto",1])


let hfind_default key value_if_not_found h =
  try Hashtbl.find h key
  with Not_found ->
    (Hashtbl.add h key (value_if_not_found ()); Hashtbl.find h key)

(* not as easy as Perl  $h->{key}++; but still possible *)
let hupdate_default key op value_if_not_found h =
  let old = hfind_default key value_if_not_found h in
  Hashtbl.replace h key (op old)


let hfind_option key h =
  optionise (fun () -> Hashtbl.find h key)


(* see below: let hkeys h = ... *)


(*****************************************************************************)
(* Hash sets *)
(*****************************************************************************)

type 'a hashset = ('a, bool) Hashtbl.t
  (* with sexp *)

let hashset_to_list h = hash_to_list h +> List.map fst

let hkeys h =
  let hkey = Hashtbl.create 101 in
  h +> Hashtbl.iter (fun k v -> Hashtbl.replace hkey k true);
  hashset_to_list hkey

let group_assoc_bykey_eff2 xs =
  let h = Hashtbl.create 101 in
  xs +> List.iter (fun (k, v) -> Hashtbl.add h k v);
  let keys = hkeys h in
  keys +> List.map (fun k -> k, Hashtbl.find_all h k)

let group_assoc_bykey_eff xs =
    group_assoc_bykey_eff2 xs

(*****************************************************************************)
(* Stack *)
(*****************************************************************************)
type 'a stack = 'a list
  (* with sexp *)

let (empty_stack: 'a stack) = []
let (push: 'a -> 'a stack -> 'a stack) = fun x xs -> x::xs
let (top: 'a stack -> 'a) = List.hd
let (pop: 'a stack -> 'a stack) = List.tl

let top_option = function
  | [] -> None
  | x::xs -> Some x




(* now in prelude:
 * let push2 v l = l := v :: !l
 *)

let pop2 l =
  let v = List.hd !l in
  begin
    l := List.tl !l;
    v
  end


(*****************************************************************************)
(* Undoable Stack *)
(*****************************************************************************)

(* Okasaki use such structure also for having efficient data structure
 * supporting fast append.
 *)

type 'a undo_stack = 'a list * 'a list (* redo *)

let (empty_undo_stack: 'a undo_stack) =
  [], []

(* push erase the possible redo *)
let (push_undo: 'a -> 'a undo_stack -> 'a undo_stack) = fun x (undo,redo) ->
  x::undo, []

let (top_undo: 'a undo_stack -> 'a) = fun (undo, redo) ->
  List.hd undo

let (pop_undo: 'a undo_stack -> 'a undo_stack) = fun (undo, redo) ->
  match undo with
  | [] ->  failwith "empty undo stack"
  | x::xs ->
      xs, x::redo

let (undo_pop: 'a undo_stack -> 'a undo_stack) = fun (undo, redo) ->
  match redo with
  | [] -> failwith "empty redo, nothing to redo"
  | x::xs ->
      x::undo, xs

let top_undo_option = fun (undo, redo) ->
  match undo with
  | [] -> None
  | x::xs -> Some x

(*****************************************************************************)
(* Binary tree *)
(*****************************************************************************)
type 'a bintree = Leaf of 'a | Branch of ('a bintree * 'a bintree)


(*****************************************************************************)
(* N-ary tree *)
(*****************************************************************************)

(* no empty tree, must have one root at list *)
type 'a tree = Tree of 'a * ('a tree) list

let rec (tree_iter: ('a -> unit) -> 'a tree -> unit) = fun f tree ->
  match tree with
  | Tree (node, xs) ->
      f node;
      xs +> List.iter (tree_iter f)


(*****************************************************************************)
(* N-ary tree with updatable childrens *)
(*****************************************************************************)

(* no empty tree, must have one root at list *)

type 'a treeref =
  | NodeRef of 'a * 'a treeref list ref

let rec (treeref_node_iter:
(*   (('a * ('a, 'b) treeref list ref) -> unit) ->
   ('a, 'b) treeref -> unit
*) 'a)
 =
 fun f tree ->
  match tree with
(*  | LeafRef _ -> ()*)
  | NodeRef (n, xs) ->
      f (n, xs);
      !xs +> List.iter (treeref_node_iter f)

let (treeref_node_iter_with_parents:
 (*  (('a * ('a, 'b) treeref list ref) -> ('a list) -> unit) ->
   ('a, 'b) treeref -> unit)
 *) 'a)
 =
 fun f tree ->
  let rec aux acc tree =
    match tree with
(*    | LeafRef _ -> ()*)
    | NodeRef (n, xs) ->
        f (n, xs) acc ;
        !xs +> List.iter (aux (n::acc))
  in
  aux [] tree


(* ---------------------------------------------------------------------- *)
(* Leaf can seem redundant, but sometimes want to directly see if
 * a children is a leaf without looking if the list is empty.
 *)
type ('a, 'b) treeref2 =
  | NodeRef2 of 'a * ('a, 'b) treeref2 list ref
  | LeafRef2 of 'b


let rec (treeref_node_iter2:
   (('a * ('a, 'b) treeref2 list ref) -> unit) ->
   ('a, 'b) treeref2 -> unit) =
 fun f tree ->
  match tree with
  | LeafRef2 _ -> ()
  | NodeRef2 (n, xs) ->
      f (n, xs);
      !xs +> List.iter (treeref_node_iter2 f)


(*****************************************************************************)
(* Graph. Have a look too at Ograph_*.mli  *)
(*****************************************************************************)
(* todo: generalise to put in common (need 'edge (and 'c ?),
 * and take in param a display func, cos caml sux, no overloading of show :(
 * Simple implementation. Can do also matrix, or adjacent list, or pointer(ref)
 * todo: do some check (don't exist already, ...)
 *)

type 'node graph = ('node set) * (('node * 'node) set)

let (add_node: 'a -> 'a graph -> 'a graph) = fun node (nodes, arcs) ->
  (node::nodes, arcs)

let (del_node: 'a -> 'a graph -> 'a graph) = fun node (nodes, arcs) ->
  (nodes $-$ set [node], arcs)
(* could do more job:
  let _ = assert (successors node (nodes, arcs) = []) in
   +> List.filter (fun (src, dst) -> dst != node))
*)
let (add_arc: ('a * 'a) -> 'a graph -> 'a graph) = fun arc (nodes, arcs) ->
  (nodes, set [arc] $+$ arcs)

let (del_arc: ('a * 'a) -> 'a graph -> 'a graph) = fun arc (nodes, arcs) ->
  (nodes, arcs +> List.filter (fun a -> not (arc = a)))

let (successors: 'a -> 'a graph -> 'a set) = fun x (nodes, arcs) ->
  arcs +> List.filter (fun (src, dst) -> src = x) +> List.map snd

let (predecessors: 'a -> 'a graph -> 'a set) = fun x (nodes, arcs) ->
  arcs +> List.filter (fun (src, dst) -> dst = x) +> List.map fst

let (nodes: 'a graph -> 'a set) = fun (nodes, arcs) -> nodes

(* pre: no cycle *)
let rec (fold_upward: ('b -> 'a -> 'b) -> 'a set -> 'b -> 'a graph  -> 'b) =
 fun f xs acc graph ->
  match xs with
  | [] -> acc
  | x::xs -> (f acc x)
        +> (fun newacc -> fold_upward f (graph +> predecessors x) newacc graph)
        +> (fun newacc -> fold_upward f xs newacc graph)
   (* TODO avoid already visited *)

let empty_graph = ([], [])



(*
let (add_arcs_toward: int -> (int list) -> 'a graph -> 'a graph) = fun i xs ->
  function
    (nodes, arcs) -> (nodes, (List.map (fun j -> (j,i) ) xs) @ arcs)
let (del_arcs_toward: int -> (int list) -> 'a graph -> 'a graph)= fun i xs g ->
    List.fold_left (fun acc el -> del_arc (el, i) acc) g xs
let (add_arcs_from: int -> (int list) -> 'a graph -> 'a graph) = fun i xs ->
 function
    (nodes, arcs) -> (nodes, (List.map (fun j -> (i,j) ) xs) @ arcs)


let (del_node: (int * 'node) -> 'node graph -> 'node graph) = fun node ->
 function (nodes, arcs) ->
  let newnodes = List.filter (fun a -> not (node = a)) nodes in
    if newnodes = nodes then (raise Not_found) else (newnodes, arcs)
let (replace_node: int -> 'node -> 'node graph -> 'node graph) = fun i n ->
 function (nodes, arcs) ->
  let newnodes = List.filter (fun (j,_) -> not (i = j)) nodes in
    ((i,n)::newnodes, arcs)
let (get_node: int -> 'node graph -> 'node) = fun i -> function
    (nodes, arcs) -> List.assoc i nodes

let (get_free: 'a graph -> int) = function
    (nodes, arcs) -> (maximum (List.map fst nodes))+1
(* require no cycle !!
  TODO if cycle check that we have already visited a node *)
let rec (succ_all: int -> 'a graph -> (int list)) = fun i -> function
    (nodes, arcs) as g ->
      let direct = succ i g in
      union direct (union_list (List.map (fun i -> succ_all i g) direct))
let rec (pred_all: int -> 'a graph -> (int list)) = fun i -> function
    (nodes, arcs) as g ->
      let direct = pred i g in
      union direct (union_list (List.map (fun i -> pred_all i g) direct))
(* require that the nodes are different !! *)
let rec (equal: 'a graph -> 'a graph -> bool) = fun g1 g2 ->
  let ((nodes1, arcs1),(nodes2, arcs2)) = (g1,g2) in
  try
   (* do 2 things, check same length and to assoc *)
    let conv = assoc_map nodes1 nodes2 in
    List.for_all (fun (i1,i2) ->
       List.mem (List.assoc i1 conv, List.assoc i2 conv) arcs2)
     arcs1
      && (List.length arcs1 = List.length arcs2)
    (* could think that only forall is needed, but need check same length too*)
  with _ -> false

let (display: 'a graph -> ('a -> unit) -> unit) = fun g display_func ->
  let rec aux depth i =
    print_n depth " ";
    print_int i; print_string "->"; display_func (get_node i g);
    print_string "\n";
    List.iter (aux (depth+2)) (succ i g)
  in aux 0 1

let (display_dot: 'a graph -> ('a -> string) -> unit)= fun (nodes,arcs) func ->
  let file = open_out "test.dot" in
  output_string file "digraph misc {\n" ;
  List.iter (fun (n, node) ->
    output_int file n; output_string file " [label=\"";
    output_string file (func node); output_string file " \"];\n"; ) nodes;
  List.iter (fun (i1,i2) ->  output_int file i1 ; output_string file " -> " ;
    output_int file i2 ; output_string file " ;\n"; ) arcs;
  output_string file "}\n" ;
  close_out file;
  let status = Unix.system "viewdot test.dot" in
  ()
(* todo: faire = graphe (int can change !!! => cannot make simply =)
   reassign number first !!
 *)

(* todo: mettre diff(modulo = !!) en rouge *)
let (display_dot2: 'a graph -> 'a graph -> ('a -> string) -> unit) =
  fun (nodes1, arcs1) (nodes2, arcs2) func ->
  let file = open_out "test.dot" in
  output_string file "digraph misc {\n" ;
  output_string file "rotate = 90;\n";
  List.iter (fun (n, node) ->
    output_string file "100"; output_int file n;
    output_string file " [label=\"";
    output_string file (func node); output_string file " \"];\n"; ) nodes1;
  List.iter (fun (n, node) ->
    output_string file "200"; output_int file n;
    output_string file " [label=\"";
    output_string file (func node); output_string file " \"];\n"; ) nodes2;
  List.iter (fun (i1,i2) ->
    output_string file "100"; output_int file i1 ; output_string file " -> " ;
    output_string file "100"; output_int file i2 ; output_string file " ;\n";
    )
   arcs1;
  List.iter (fun (i1,i2) ->
    output_string file "200"; output_int file i1 ; output_string file " -> " ;
    output_string file "200"; output_int file i2 ; output_string file " ;\n"; )
   arcs2;
(*  output_string file "500 -> 1001; 500 -> 2001}\n" ; *)
  output_string file "}\n" ;
  close_out file;
  let status = Unix.system "viewdot test.dot" in
  ()


*)
(*****************************************************************************)
(* Generic op *)
(*****************************************************************************)
(* overloading *)

let map = List.map (* note: really really slow, use rev_map if possible *)
let filter = List.filter
let fold = List.fold_left
let member = List.mem
let iter = List.iter
let find = List.find
let exists = List.exists
let forall = List.for_all
let sort = List.sort
let length = List.length
let head = List.hd
let tail = List.tl
let is_singleton = fun xs -> List.length xs = 1

let tail_map f l = (* tail recursive map, using rev *)
  let rec loop acc = function
      [] -> acc
    | x::xs -> loop ((f x) :: acc) xs in
  List.rev(loop [] l)

(*****************************************************************************)
(* Geometry (raytracer) *)
(*****************************************************************************)

type vector = (float * float * float)
type point = vector
type color = vector (* color(0-1) *)

(* todo: factorise *)
let (dotproduct: vector * vector -> float) =
  fun ((x1,y1,z1),(x2,y2,z2)) -> (x1*.x2 +. y1*.y2 +. z1*.z2)
let (vector_length: vector -> float) =
  fun (x,y,z) -> sqrt (square x +. square y +. square z)
let (minus_point: point * point -> vector) =
  fun ((x1,y1,z1),(x2,y2,z2)) -> ((x1 -. x2),(y1 -. y2),(z1 -. z2))
let (distance: point * point -> float) =
  fun (x1, x2) -> vector_length (minus_point (x2,x1))
let (normalise: vector -> vector) =
  fun (x,y,z) ->
    let len = vector_length (x,y,z) in (x /. len, y /. len, z /. len)
let (mult_coeff: vector -> float -> vector) =
  fun (x,y,z) c -> (x *. c, y *. c, z *. c)
let (add_vector: vector -> vector -> vector) =
  fun v1 v2 -> let ((x1,y1,z1),(x2,y2,z2)) = (v1,v2) in
  (x1+.x2, y1+.y2, z1+.z2)
let (mult_vector: vector -> vector -> vector) =
  fun v1 v2 -> let ((x1,y1,z1),(x2,y2,z2)) = (v1,v2) in
  (x1*.x2, y1*.y2, z1*.z2)
let sum_vector = List.fold_left add_vector (0.0,0.0,0.0)

(*****************************************************************************)
(* Pics (raytracer) *)
(*****************************************************************************)

type pixel = (int * int * int) (* RGB *)

(* required pixel list in row major order, line after line *)
let (write_ppm: int -> int -> (pixel list) -> string -> unit) = fun
  width height xs filename ->
    let chan = open_out filename in
    begin
     output_string chan "P6\n";
     output_string chan ((string_of_int width)  ^ "\n");
     output_string chan ((string_of_int height) ^ "\n");
     output_string chan "255\n";
     List.iter (fun (r,g,b) ->
       List.iter (fun byt -> output_byte chan byt) [r;g;b]
	       ) xs;
     close_out chan
    end

(*****************************************************************************)
(* Diff (lfs) *)
(*****************************************************************************)
type diff = Match | BnotinA | AnotinB

let (diff: (int -> int -> diff -> unit)-> (string list * string list) -> unit)=
  fun f (xs,ys) ->
    let file1 = "/tmp/diff1-" ^ (string_of_int (Unix.getuid ())) in
    let file2 = "/tmp/diff2-" ^ (string_of_int (Unix.getuid ())) in
    let fileresult = "/tmp/diffresult-" ^ (string_of_int (Unix.getuid ())) in
    write_file ~file:file1 (unwords xs);
    write_file ~file:file2 (unwords ys);
    command2
      ("diff --side-by-side -W 1 " ^ file1 ^ " " ^ file2 ^ " > " ^ fileresult);
    let res = cat fileresult in
    let a = ref 0 in
    let b = ref 0 in
    res +> List.iter (fun s ->
      match s with
      | ("" | " ") -> f !a !b Match; incr a; incr b;
      | ">" -> f !a !b BnotinA; incr b;
      | ("|" | "/" | "\\" ) ->
          f !a !b BnotinA; f !a !b AnotinB; incr a; incr b;
      | "<" -> f !a !b AnotinB; incr a;
      | _ -> raise (Impossible 3)
    )
(*
let _ =
  diff
    ["0";"a";"b";"c";"d";    "f";"g";"h";"j";"q";            "z"]
    [    "a";"b";"c";"d";"e";"f";"g";"i";"j";"k";"r";"x";"y";"z"]
   (fun x y -> pr "match")
   (fun x y -> pr "a_not_in_b")
   (fun x y -> pr "b_not_in_a")
*)

let (diff2: (int -> int -> diff -> unit) -> (string * string) -> unit) =
 fun f (xstr,ystr) ->
    write_file ~file:"/tmp/diff1" xstr;
    write_file ~file:"/tmp/diff2" ystr;
    command2
     ("diff --side-by-side --left-column -W 1 " ^
      "/tmp/diff1 /tmp/diff2 > /tmp/diffresult");
    let res = cat "/tmp/diffresult" in
    let a = ref 0 in
    let b = ref 0 in
    res +> List.iter (fun s ->
      match s with
      | "(" -> f !a !b Match; incr a; incr b;
      | ">" -> f !a !b BnotinA; incr b;
      | "|" -> f !a !b BnotinA; f !a !b AnotinB; incr a; incr b;
      | "<" -> f !a !b AnotinB; incr a;
      | _ -> raise (Impossible 4)
    )


(*****************************************************************************)
(* parser combinators *)
(*****************************************************************************)

(* cf parser_combinators.ml
 *
 * Could also use ocaml stream. but not backtrack and forced to do LL,
 * so combinators are better.
 *
 *)


(*****************************************************************************)
(* Parser related (cocci) *)
(*****************************************************************************)

type parse_info = {
    str: string;
    charpos: int;

    line: int;
    column: int;
    file: filename;
  }
  (* with sexp *)

let fake_parse_info = {
  charpos = -1; str = "";
  line = -1; column = -1; file = "";
}

let string_of_parse_info x =
  spf "%s at %s:%d:%d" x.str x.file x.line x.column
let string_of_parse_info_bis x =
  spf "%s:%d:%d" x.file x.line x.column

let (info_from_charpos2: int -> filename -> (int * int * string)) =
 fun charpos filename ->

  (* Currently lexing.ml does not handle the line number position.
   * Even if there is some fields in the lexing structure, they are not
   * maintained by the lexing engine :( So the following code does not work:
   *   let pos = Lexing.lexeme_end_p lexbuf in
   *   sprintf "at file %s, line %d, char %d" pos.pos_fname pos.pos_lnum
   *      (pos.pos_cnum - pos.pos_bol) in
   * Hence this function to overcome the previous limitation.
   *)
  let chan = open_in filename in
  let linen  = ref 0 in
  let posl   = ref 0 in
  let rec charpos_to_pos_aux last_valid =
    let s =
      try Some (input_line chan)
      with End_of_file when charpos = last_valid -> None in
    incr linen;
    match s with
      Some s ->
	let s = s ^ "\n" in
	let slength = String.length s in
	if (!posl + slength > charpos)
	then begin
	  close_in chan;
	  (!linen, charpos - !posl, s)
	end
	else begin
	  posl := !posl + slength;
	  charpos_to_pos_aux !posl;
	end
    | None -> (!linen, charpos - !posl, "\n")
  in
  let res = charpos_to_pos_aux 0 in
  close_in chan;
  res

let info_from_charpos a b =
  profile_code "Common.info_from_charpos" (fun () -> info_from_charpos2 a b)



let full_charpos_to_pos2 = fun filename ->

  let size = (filesize filename + 2) in

    let arr = Array.make size  (0,0) in

    let chan = open_in filename in

    let charpos   = ref 0 in
    let line  = ref 0 in

    let rec full_charpos_to_pos_aux () =
     try
       let s = (input_line chan) in
       incr line;

       (* '... +1 do'  cos input_line don't return the trailing \n *)
       let slength = String.length s in
       for i = 0 to (slength - 1) + 1 do
         arr.(!charpos + i) <- (!line, i);
       done;
       charpos := !charpos + slength + 1;
       full_charpos_to_pos_aux();

     with End_of_file ->
       for i = !charpos to Array.length arr - 1 do
         arr.(i) <- (!line, 0);
       done;
       ();
    in
    begin
      full_charpos_to_pos_aux ();
      close_in chan;
      arr
    end
let full_charpos_to_pos a =
  profile_code "Common.full_charpos_to_pos" (fun () -> full_charpos_to_pos2 a)

(*---------------------------------------------------------------------------*)
(* Decalage is here to handle stuff such as cpp which include file and who
 * can make shift.
 *)
let (error_messagebis: filename -> (string * int) -> int -> string)=
 fun filename (lexeme, lexstart) decalage ->

  let charpos = lexstart      + decalage in
  let tok = lexeme in
  let (line, pos, linecontent) =  info_from_charpos charpos filename in
  Printf.sprintf "File \"%s\", line %d, column %d, charpos = %d\
    \n  around = '%s',\n  whole content = %s"
    filename line pos charpos tok (chop linecontent)

let error_message = fun filename (lexeme, lexstart) ->
  try error_messagebis filename (lexeme, lexstart) 0
  with
    End_of_file ->
      ("PB in Common.error_message, position " ^ string_of_int lexstart ^
       " given out of file:" ^ filename)



let error_message_short = fun filename (lexeme, lexstart) ->
  try
  let charpos = lexstart in
  let (line, pos, linecontent) =  info_from_charpos charpos filename in
  Printf.sprintf "File \"%s\", line %d"  filename line

  with End_of_file ->
    begin
      ("PB in Common.error_message, position " ^ string_of_int lexstart ^
          " given out of file:" ^ filename);
    end



(*****************************************************************************)
(* Regression testing bis (cocci) *)
(*****************************************************************************)

(* todo: keep also size of file, compute md5sum? cos maybe the file
 * has changed!
 *
 * todo: could also compute the date, or some version info of the program,
 * can record the first date when was found a OK, the last date where
 * was ok, and then first date when found fail. So the
 * Common.Ok would have more information that would be passed
 * to the Common.Pb of date * date * date * string   peut etre.
 *
 * todo? maybe use plain text file instead of marshalling.
 *)

type score_result = Ok | Pb of string | PbKnown of string
 (* with sexp *)
type score = (string (* usually a filename *), score_result) Hashtbl.t
 (* with sexp *)
type score_list = (string (* usually a filename *) * score_result) list
 (* with sexp *)

let empty_score () = (Hashtbl.create 101 : score)

let save_score score path =
  write_value score path

let load_score path () =
  read_value path

(* be insensitive to newlines, to allow improvements in the error message
formatting *)
let close_enough s1 s2 =
  let first = String.concat " " (Str.split (Str.regexp "\n") s1) in
  let second = String.concat " " (Str.split (Str.regexp "\n") s2) in
  let first = String.concat " " (Str.split (Str.regexp "  +") first) in
  let second = String.concat " " (Str.split (Str.regexp "  +") second) in
  first = second

let regression_testing_vs newscore bestscore =

  let newbestscore = empty_score () in

  let allres =
    (hash_to_list newscore +> List.map fst)
      $+$
    (hash_to_list bestscore +> List.map fst)
  in
  begin
    allres +> List.iter (fun res ->
      match
        optionise (fun () -> Hashtbl.find newscore res),
        optionise (fun () -> Hashtbl.find bestscore res)
      with
      | None, None -> raise (Impossible 5)
      | Some x, None ->
          Printf.printf "new test file appeared: %s\n" res;
          Hashtbl.add newbestscore res x;
      | None, Some x ->
          Printf.printf "old test file disappeared: %s\n" res;
      | Some newone, Some bestone ->
          (match newone, bestone with
          | Ok, Ok ->
              Hashtbl.add newbestscore res Ok
          | Pb x, Ok | PbKnown x, Ok ->
              Printf.printf
		"PBBBBBBBB: a test file does not work anymore!!! : %s\n" res;
              Printf.printf "Error : %s\n" x;
              Hashtbl.add newbestscore res Ok
          | Ok, Pb x | Ok, PbKnown x ->
              Printf.printf "Great: a test file now works: %s\n" res;
              Hashtbl.add newbestscore res Ok
          | Pb x, Pb y | PbKnown x, PbKnown y ->
              Hashtbl.add newbestscore res (Pb x);
              if not (close_enough x y)
              then begin
                Printf.printf
		  "Semipb: still error but not same error : %s\n" res;
                Printf.printf "%s\n" (chop ("Old error: " ^ y));
                Printf.printf "New error: %s\n" x;
              end
          | Pb x, PbKnown y ->
              (* as long as known failures keep being defined by filenames,
              this can't happen *)
              Printf.printf "a test failure is no longer marked as known: %s\n" res;
              Printf.printf "New error: %s\n" x;
              Hashtbl.add newbestscore res (Pb x);
          | PbKnown x, Pb y ->
              (* same caveat as previous case *)
              Printf.printf "a test failure is now marked as known: %s\n" res;
              Printf.printf "New error: %s\n" x;
              Hashtbl.add newbestscore res (Pb x);
          )
    );
    flush stdout; flush stderr;
    newbestscore
  end

let regression_testing newscore best_score_file =

  pr2 ("regression file: "^ best_score_file);
  let (bestscore : score) =
    if not (Sys.file_exists best_score_file)
    then write_value (empty_score()) best_score_file;
    get_value best_score_file
  in
  let newbestscore = regression_testing_vs newscore bestscore in
  write_value newbestscore (best_score_file ^ ".old");
  write_value newbestscore best_score_file;
  ()

let total_scores score =
  let apparent_total = hash_to_list score +> List.length in
  let known_failures = hash_to_list score +> List.filter
    (fun (s, v) -> match v with
      PbKnown _ -> true
      | _ -> false
    ) +> List.length in
  let good  = hash_to_list score +> List.filter
    (fun (s, v) -> v = Ok) +> List.length in
  good, apparent_total - known_failures, known_failures


let print_total_score score =
  pr2 "total score";
  let (good, total, known_failures) = total_scores score in
  pr2 (Printf.sprintf "good = %d/%d + %d known failures" good total known_failures)

(*****************************************************************************)
(* Scope management (cocci) *)
(*****************************************************************************)

(* could also make a function Common.make_scope_functions that return
 * the new_scope, del_scope, do_in_scope, add_env. Kind of functor :)
 *)

type ('a, 'b) scoped_env = ('a, 'b) assoc list

let rec lookup_env k env =
  match env with
  | [] -> raise Not_found
  | []::zs -> lookup_env k zs
  | ((k',v)::xs)::zs ->
      if k = k'
      then v
      else lookup_env k (xs::zs)

let new_scope scoped_env = scoped_env := []::!scoped_env
let del_scope scoped_env = scoped_env := List.tl !scoped_env

let add_in_scope scoped_env def =
  let (current, older) = uncons !scoped_env in
  scoped_env := (def::current)::older





(* note that ocaml hashtbl store also old value of a binding when add
 * add a newbinding; that's why del_scope works
 *)

type ('a, 'b) scoped_h_env = {
  scoped_h : ('a, 'b) Hashtbl.t;
  scoped_list : ('a, 'b) assoc list;
}

let empty_scoped_h_env () = {
  scoped_h = Hashtbl.create 101;
  scoped_list = [[]];
}
let clone_scoped_h_env x =
  { scoped_h = Hashtbl.copy x.scoped_h;
    scoped_list = x.scoped_list;
  }

let lookup_h_env k env =
  Hashtbl.find env.scoped_h k

let new_scope_h scoped_env =
  scoped_env := {!scoped_env with scoped_list = []::!scoped_env.scoped_list}

let del_scope_h scoped_env =
  begin
    List.hd !scoped_env.scoped_list +> List.iter (fun (k, v) ->
      Hashtbl.remove !scoped_env.scoped_h k
    );
    scoped_env := {!scoped_env with scoped_list =
        List.tl !scoped_env.scoped_list
    }
  end

let clean_scope_h scoped_env = (* keep only top level (last scope) *)
  let rec loop _ =
    match (!scoped_env).scoped_list with
      [] | [_] -> ()
    | _::_ -> del_scope_h scoped_env; loop () in
  loop()

let add_in_scope_h x (k,v) =
  begin
    Hashtbl.add !x.scoped_h k v;
    x := { !x with scoped_list =
        ((k,v)::(List.hd !x.scoped_list))::(List.tl !x.scoped_list);
    };
  end

(*****************************************************************************)
(* Terminal *)
(*****************************************************************************)

(* let ansi_terminal = ref true *)

let (_execute_and_show_progress_func:  (int (* length *) -> ((unit -> unit) -> unit) -> unit) ref)
 = ref
  (fun a b ->
    failwith "no execute  yet, have you included common_extra.cmo?"
  )



let execute_and_show_progress len f =
    !_execute_and_show_progress_func len f


(* now in common_extra.ml:
 * let execute_and_show_progress len f = ...
 *)

(*****************************************************************************)
(* Random *)
(*****************************************************************************)

let _init_random = Random.self_init ()
(*
let random_insert i l =
    let p = Random.int (length l +1)
    in let rec insert i p l =
      if (p = 0) then i::l else (hd l)::insert i (p-1) (tl l)
    in insert i p l

let rec randomize_list = function
  []  -> []
  | a::l -> random_insert a (randomize_list l)
*)
let random_list xs =
  List.nth xs (Random.int (length xs))

(* todo_opti: use fisher/yates algorithm.
 * ref: http://en.wikipedia.org/wiki/Knuth_shuffle
 *
 * public static void shuffle (int[] array)
 * {
 *  Random rng = new Random ();
 *  int n = array.length;
 *  while (--n > 0)
 *  {
 *    int k = rng.nextInt(n + 1);  // 0 <= k <= n (!)
 *    int temp = array[n];
 *    array[n] = array[k];
 *    array[k] = temp;
 *   }
 * }

 *)
let randomize_list xs =
  let permut = permutation xs in
  random_list permut

let cmdline_actions () =
  [
    "-test_check_stack", "  <limit>",
    mk_action_1_arg test_check_stack_size;
  ]


(*****************************************************************************)
(* Postlude *)
(*****************************************************************************)
(* stuff put here cos of of forward definition limitation of ocaml *)


(* Infix trick, seen in jane street lib and harrop's code, and maybe in GMP *)
module Infix = struct
  let (+>) = (+>)
  let (==~) = (==~)
  let (=~) = (=~)
end


let main_boilerplate f =
  if not (!Sys.interactive) then
    exn_to_real_unixexit (fun () ->

      Sys.set_signal Sys.sigint (Sys.Signal_handle   (fun _ ->
        pr2 "C-c intercepted, will do some cleaning before exiting";
        (* But if do some try ... with e -> and if do not reraise the exn,
         * the bubble never goes at top and so I cannot really C-c.
         *
         * A solution would be to not raise, but do the erase_temp_file in the
         * syshandler, here, and then exit.
         * The current solution is to not do some wild  try ... with e
         * by having in the exn handler a case: UnixExit x -> raise ... | e ->
         *)
        Sys.set_signal Sys.sigint Sys.Signal_default;
        raise (UnixExit (-1))
      ));

      (* The finalize below makes it tedious to go back to exn when use
       * 'back' in the debugger. Hence this special case. But the
       * Common.debugger will be set in main(), so too late, so
       * have to be quicker
       *)
      if Sys.argv +> Array.to_list +> List.exists (fun x -> x = "-debugger")
      then debugger := true;

      finalize          (fun ()->
        pp_do_in_zero_box (fun () ->
          f(); (* <---- here it is *)
        ))
       (fun()->
         if !profile <> PNONE
         then pr2 (profile_diagnostic ());
         erase_temp_files ();
	 clear_pr2_once()
       )
    )
(* let _ = if not !Sys.interactive then (main ()) *)


(* based on code found in cameleon from maxence guesdon *)
let md5sum_of_string s =
  let com = spf "echo %s | md5sum | cut -d\" \" -f 1"
      (Filename.quote s)
  in
  match cmd_to_list com with
  | [s] ->
      (*pr2 s;*)
      s
  | _ -> failwith "md5sum_of_string wrong output"

(* julia: convert something printed using format to print into a string *)
let do_format_to_string nl f =
  let acc = ref [] in
  let (pr,flush) = Format.get_formatter_output_functions() in
  Format.set_formatter_output_functions
    (fun s p n -> acc := String.sub s p n :: !acc)
    (fun _ -> ());
  let _ = f() in
  (if nl then Format.print_newline());
  Format.print_flush();
  Format.set_formatter_output_functions pr flush;
  String.concat "" (List.rev !acc)

let format_to_string f = do_format_to_string true f

let format_to_string_nonl f = do_format_to_string false f

(*****************************************************************************)
(* Misc/test *)
(*****************************************************************************)

let (generic_print: 'a -> string -> string) = fun v typ ->
  write_value v "/tmp/generic_print";
  command2
   ("printf 'let (v:" ^ typ ^ ")= Common.get_value \"/tmp/generic_print\" " ^
     " in v;;' " ^
     " | calc.top > /tmp/result_generic_print");
   cat "/tmp/result_generic_print"
   +> drop_while (fun e -> not (e =~ "^#.*")) +> tail
   +> unlines
   +> (fun s ->
       if (s =~ ".*= \\(.+\\)")
       then matched1 s
       else "error in generic_print, not good format:" ^ s)

(* let main () = pr (generic_print [1;2;3;4] "int list") *)

class ['a] olist (ys: 'a list) =
  object(o)
    val xs = ys
    method view = xs
(*    method fold f a = List.fold_left f a xs *)
    method fold : 'b. ('b -> 'a -> 'b) -> 'b -> 'b =
      fun f accu -> List.fold_left f accu xs
  end

module StringSet = Set.Make (String)

(* --------------------------------------------------------------------- *)

type 'a dll = DElem of 'a dll option ref * 'a * 'a dll option ref

let get_dll cell =
  match !cell with
    None -> failwith "bad cell"
  | Some x -> x

let add_first_dll hd x =
  let (DElem(bprev,_,bnext)) as bef = hd in
  let (DElem(aprev,_,anext)) as aft = get_dll bnext in
  let self = DElem(ref (Some bef),x,ref (Some aft)) in
  bnext := Some self; aprev := Some self;
  self

let remove_last_dll hd =
  let (DElem(aprev,_,anext)) as aft = hd in
  let (DElem(dprev,_,dnext)) as drop = get_dll aprev in
  let (DElem(bprev,_,bnext)) as bef = get_dll dprev in
  aprev := Some bef; bnext := Some aft;
  drop

let create_bounded_cache n hval =
  let tbl = Hashtbl.create 101 in
  let prev = ref None in
  let next = ref None in
  let lst = DElem (prev,hval,next) in
  prev := Some lst; next := Some lst;
  (n,ref 0,tbl,lst)

let find_bounded_cache (n,cur,tbl,lst) x =
  try
    let DElem(prev,hval,next) = Hashtbl.find tbl x in
    let _ = remove_last_dll (get_dll next) in
    let _ = add_first_dll lst hval in
    profile_code ("ok"^(string_of_int n)) (fun _ -> snd hval)
  with x ->
    (profile_code ("miss"^(string_of_int n)) (fun _ -> ());
    raise x)

let extend_bounded_cache (n,cur,tbl,lst) x v =
  cur := !cur + 1;
  (if !cur > n
  then
    for i = 1 to (n/2) do
      let DElem(prev,hval,next) = remove_last_dll lst in
      Hashtbl.remove tbl (fst hval);
      cur := !cur - 1
    done);
  let elem = add_first_dll lst (x,v) in
  profile_code ("add"^(string_of_int n)) (fun _ -> ());
  Hashtbl.add tbl x elem
