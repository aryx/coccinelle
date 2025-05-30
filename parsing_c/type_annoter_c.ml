(* Yoann Padioleau
 *
 * Copyright (C) 2010, University of Copenhagen DIKU and INRIA.
 * Copyright (C) 2007, 2008 Ecole des Mines de Nantes,
 * Copyright (C) 2009 University of Urbana Champaign
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License (GPL)
 * version 2 as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * file license.txt for more details.
 *)

open Common

open Ast_c

module Lib = Lib_parsing_c
module IC = Includes_cache

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* History:
 *  - Done a first type checker in 2002, cf typing-semantic/, but
 *    was assuming that have all type info, and so was assuming had called
 *    cpp and everything was right.
 *  - Wrote this file, in 2006?, as we added pattern matching on type
 *    in coccinelle. Partial type annotater.
 *  - Julia extended it in 2008? to have localvar/notlocalvar and
 *    test/notest information, again used by coccinelle.
 *  - I extended it in Fall 2008 to have more type information for the
 *    global analysis. I also added some optimisations to process
 *    included code faster.
 *
 *
 * Design choices. Can either do:
 *  - a kind of inferer
 *     - can first do a simple inferer, that just pass context
 *     - then a real inferer, managing partial info.
 *    type context = fullType option
 *
 *  - extract the information from the .h files
 *    (so no inference at all needed)
 *
 * Difference with julia's code in parsing_cocci/type_infer.ml:
 *  - She handles just the variable namespace. She does not type
 *    field access or enum or macros. This is because cocci programs are
 *     usually simple and have no structure definition or macro definitions
 *     that we need to type anyway.
 *  - She does more propagation.
 *  - She does not have to handle the typedef isomorphism which force me
 *    to use those typedef_fix and type_unfold_one_step
 *  - She does not handle I think the function pointer C isomorphism.
 *
 *  - She has a cleaner type_cocci without any info. In my case
 *    I need to do those ugly al_type, or generate fake infos.
 *  - She has more compact code. Perhaps because she does not have to
 *    handle the extra exp_info that she added on me :) So I need those
 *    do_with_type, make_info_xxx, etc.
 *
 * Note: if need to debug this annotater, use -show_trace_profile, it can
 * help. You can also set the typedef_debug flag below.
 *
 *
 *
 * todo: expression contain types, and statements,   which in turn can contain
 * expression, so need recurse. Need define an annote_statement and
 * annotate_type.
 *
 * todo: how deal with typedef isomorphisms ? How store them in Ast_c ?
 * store all possible variations in ast_c ? a list of type instead of just
 * the type ?
 *
 * todo: how to handle multiple possible definitions for entities like
 * struct or typedefs ? Because of ifdef, we should store list of
 * possibilities sometimes.
 *
 * todo: define a new type ? like type_cocci ? where have a bool ?
 *
 * semi: How handle scope ? When search for type of field, we return
 * a type, but this type makes sense only in a certain scope.
 * We could add a tag to each typedef, structUnionName to differentiate
 * them and also associate in ast_c to the type the scope
 * of this type, the env that were used to define this type.
 *
 * todo: handle better the search in previous env, the env'. Cf the
 * termination problem in typedef_fix when I was searching in the same
 * env.
 *
 *)

(*****************************************************************************)
(* Wrappers *)
(*****************************************************************************)
let pr2, pr2_once = Common.mk_pr2_wrappers Flag_parsing_c.verbose_type

(*****************************************************************************)
(* Environment *)
(*****************************************************************************)

(* The different namespaces from stdC manual:
 *
 * You introduce two new name spaces with every block that you write.
 *
 * One name space includes all
 *  - functions,
 *  - objects,
 *  - type definitions,
 *  - and enumeration constants
 * that you declare or define within the  block.
 *
 * The other name space includes all
 *  - enumeration,
 *  - structure,
 *  - and union
 *  *tags* that you define within the block.
 *
 * You introduce a new member name space with every structure or union
 * whose content you define. You identify a member name space by the
 * type of left operand that you write for a member selection
 * operator, as in x.y or p->y. A member name space ends with the end
 * of the block in which you declare it.
 *
 * You introduce a new goto label name space with every function
 * definition you write. Each goto label name space ends with its
 * function definition.
 *)

(* But I don't try to do a type-checker, I try to "resolve" type of var
 * so don't need make difference between namespaces here.
 *
 * But, why not make simply a (string, kindstring) assoc ?
 * Because we don't want that a variable shadow a struct definition, because
 * they are still in 2 different namespace. But could for typedef,
 * because VarOrFunc and Typedef are in the same namespace.
 * But could do a record as in c_info.ml
 *)


(* This type contains all "ident" like notion of C. Each time in Ast_c
 * you have a string type (as in expression, function name, fields)
 * then you need to manage the scope of this ident.
 *
 * The wrap for StructUnionNameDef contain the whole ii, the i for
 * the string, the structUnion and the structType.
 *
 * Put Macro here ? after all the scoping rules for cpp macros is different
 * and so does not vanish after the closing '}'.
 *
 * todo: EnumDef
 *)
type namedef =
  | VarOrFunc of string * Ast_c.exp_type
  | EnumConstant of string * fullType

  (* also used for macro type aliases *)
  | TypeDef   of string * fullType
  (* the structType contains nested "idents" with struct scope *)
  | StructUnionNameDef of string * (structUnion * structType) wrap

  (* cppext: *)
  | Macro        of string * (define_kind * define_val)

module StringMap = Map.Make (String)
let singleton k v = StringMap.add k v StringMap.empty

(* Maps are used instead of lists in order to guarantee O(log(n))
   complexity when doing a lookup. The case of typedefs is a bit
   different from the others because we may want to do a second
   search, using the environment as it was when the typedef first
   searched was declared. *)

type typedefs = { defs : (fullType * typedefs * int) StringMap.t }

type nameenv = {
    level : int;
    var_or_func : Ast_c.exp_type StringMap.t;
    enum_constant : Ast_c.fullType StringMap.t;
    typedef : typedefs;
    struct_union_name_def : ((structUnion * structType) wrap) StringMap.t;
    macro : (define_kind * define_val) StringMap.t
  }

type environment = nameenv list

let includes_parse_fn file =
  let choose_includes = Includes.get_parsing_style () in
  Includes.set_parsing_style Includes.Parse_no_includes;
  let ret = Parse_c.parse_c_and_cpp false false file in
  Includes.set_parsing_style choose_includes;
  List.map fst (fst ret)

(* ------------------------------------------------------------ *)
(* can be modified by the init_env function below, by
 * the file environment_unix.h
 *)

let empty_frame =
  { level = 0;
    var_or_func = StringMap.empty;
    enum_constant = StringMap.empty;
    typedef = { defs = StringMap.empty };
    struct_union_name_def = StringMap.empty;
    macro = StringMap.empty; }

let initial_env = ref [
  { empty_frame with
    var_or_func =
    singleton
      "NULL"
      (Lib.al_type (Parse_c.type_of_string "void *"),Ast_c.NotLocalVar) }
  (*
   VarOrFunc("malloc",
            (Lib.al_type(Parse_c.type_of_string "void* ( * )(int size)"),
	    Ast_c.NotLocalVar));
   VarOrFunc("free",
            (Lib.al_type(Parse_c.type_of_string "void ( * )(void *ptr)"),
	    Ast_c.NotLocalVar));
  *)
]

let _scoped_env = ref !initial_env
let build_env prev level =
  let rec ret = function
    | [] -> assert false
    | hd :: tl ->
	if hd.level = level then
	  { hd with typedef = prev }
	else
	  ret tl in
  [ret !_scoped_env]

let typedef_debug = ref false


(* ------------------------------------------------------------ *)
(* generic, lookup and also return remaining env for further lookup *)

let member_env lookupf env =
  try
    let _ = lookupf env in
    true
  with Not_found -> false

(* ------------------------------------------------------------ *)

let rec lookup_var s env =
  match env with
  | [] -> raise Not_found
  | env :: rest ->
      try StringMap.find s env.var_or_func
      with _ -> lookup_var s rest

let member_env_lookup_var s env =
  match env with
  | [] -> false
  | env :: _ -> StringMap.mem s env.var_or_func

let lookup_typedef (s : string) (env : environment) =
  if !typedef_debug then pr2 ("looking for: " ^ s);
  match env with
  | [] -> raise Not_found
  | env :: tl ->
      let typ, prev, level = StringMap.find s env.typedef.defs in
      let res : fullType * environment = typ, build_env prev level in
      res

let member_env_lookup_typedef (s : string) (env : environment) =
  match env with
  | [] -> false
  | env :: _ -> StringMap.mem s env.typedef.defs

let lookup_structunion (_su, s) env =
  match env with
  | [] -> raise Not_found
  | env :: _ -> StringMap.find s env.struct_union_name_def

let member_env_lookup_structunion (_su, s) env =
  match env with
  | [] -> false
  | env :: _ -> StringMap.mem s env.struct_union_name_def

let lookup_macro s env =
  match env with
  | [] -> raise Not_found
  | env :: _ -> StringMap.find s env.macro

let member_env_lookup_macro s env =
  match env with
  | [] -> false
  | env :: _ -> StringMap.mem s env.macro

let lookup_enum s env =
  match env with
  | [] -> raise Not_found
  | env :: _ -> StringMap.find s env.enum_constant

let member_env_lookup_enum s env =
  match env with
  | [] -> false
  | env :: _ -> StringMap.mem s env.enum_constant

(* ------------------------------------------------------------ *)

let add_cache_binding_in_scope namedef =
  let (current, older) = Common.uncons !_scoped_env in
  let new_frame fr =
    match namedef with
      | IC.RetVarOrFunc (s, typ) ->
	  {fr with
	   var_or_func = StringMap.add s typ fr.var_or_func}
      | IC.RetTypeDef   (s, typ) ->
	  let cv = typ, fr.typedef, fr.level in
	  let new_typedef_c : typedefs = { defs = StringMap.add s cv fr.typedef.defs } in
	  {fr with typedef = new_typedef_c}
      | IC.RetStructUnionNameDef (s, (su, typ)) ->
	  {fr with
	   struct_union_name_def = StringMap.add s (su, typ) fr.struct_union_name_def}
      | IC.RetEnumConstant (s, body) ->
	  {fr with
	   enum_constant = StringMap.add s body fr.enum_constant} in
  (* These are global, so have to reflect them in all the frames. *)
  _scoped_env := (new_frame current)::(List.map new_frame older)

(* Has side-effects on the environment.
 * TODO: profile? *)
let get_type_from_includes_cache file name exp_types on_success on_failure =
  let file_bindings =
    IC.get_types_from_name_cache
      file name exp_types includes_parse_fn in
  List.iter add_cache_binding_in_scope file_bindings;
  match file_bindings with
    [] -> on_failure ()
  | _ -> on_success ()


(*****************************************************************************)
(* "type-lookup"  *)
(*****************************************************************************)

(* find_final_type is used to know to what type a field correspond in
 * x.foo. Sometimes the type of x is a typedef or a structName in which
 * case we must look in environment to find the complete type, here
 * structUnion that contains the information.
 *
 * Because in C one can redefine in nested blocks some typedefs,
 * struct, or variables, we have a static scoping resolving process.
 * So, when we look for the type of a var, if this var is in an
 * enclosing block, then maybe its type refer to a typdef of this
 * enclosing block, so must restart the "type-resolving" of this
 * typedef from this enclosing block, not from the bottom. So our
 * "resolving-type functions" take an env and also return an env from
 * where the next search must be performed. *)

(*
let rec find_final_type ty env =

  match Ast_c.unwrap_typeC ty with
  | BaseType x  -> (BaseType x) +> Ast_c.rewrap_typeC ty

  | Pointer t -> (Pointer (find_final_type t env))  +> Ast_c.rewrap_typeC ty
  | Array (e, t) -> Array (e, find_final_type t env) +> Ast_c.rewrap_typeC ty

  | StructUnion (sopt, su) -> StructUnion (sopt, su)  +> Ast_c.rewrap_typeC ty

  | FunctionType t -> (FunctionType t) (* todo ? *) +> Ast_c.rewrap_typeC ty
  | Enum  (s, enumt) -> (Enum  (s, enumt)) (* todo? *) +> Ast_c.rewrap_typeC ty
  | EnumName s -> (EnumName s) (* todo? *) +> Ast_c.rewrap_typeC ty

  | StructUnionName (su, s) ->
      (try
          let ((structtyp,ii), env') = lookup_structunion (su, s) env in
          Ast_c.nQ, (StructUnion (Some s, structtyp), ii)
          (* old: +> Ast_c.rewrap_typeC ty
           * but must wrap with good ii, otherwise pretty_print_c
           * will be lost and raise some Impossible
           *)
       with Not_found ->
         ty
      )

  | NamedType s ->
      (try
          let (t', env') = lookup_typedef s env in
          find_final_type t' env'
        with Not_found ->
          ty
      )

  | ParenType t -> find_final_type t env
  | Typeof e -> failwith "typeof"
*)




(* ------------------------------------------------------------ *)
let rec type_unfold_one_step ty env =
  let rec loop seen ty env =

  match Ast_c.unwrap_typeC ty with
  | NoType        -> ty
  | BaseType x    -> ty
  | Pointer t     -> ty
  | Array (e, t)  -> ty
  | Decimal (len,prec_opt) -> ty

  | StructUnion (sopt, su, optfinal, base_classes, fields) -> ty

  | FunctionType t   -> ty
  | EnumDef  (ename, base, enumt) -> ty

  | EnumName (key, id)       -> ty (* todo: look in env when will have EnumDef *)

  | ParenType t      -> ty

  | StructUnionName (su, s) ->
      (try
          let ((su,fields),ii) = lookup_structunion (su, s) env in
          Ast_c.mk_ty (StructUnion (su, Some s, None, [], fields)) ii
          (* old: +> Ast_c.rewrap_typeC ty
           * but must wrap with good ii, otherwise pretty_print_c
           * will be lost and raise some Impossible
           *)
       with Not_found ->
         ty
      )

  | TypeName name    -> ty

  | NamedType (name, _typ) ->
      let s = Ast_c.str_of_name name in
      (try
          if !typedef_debug then pr2 "type_unfold_one_step: lookup_typedef";
          let (t', env') = lookup_typedef s env in
	  if List.mem s seen (* avoid pb with recursive typedefs *)
	  then type_unfold_one_step t' env'
          else loop (s::seen) t' env
       with Not_found ->
          let f = Ast_c.file_of_info (Ast_c.info_of_name name) in
          get_type_from_includes_cache
            f s [IC.CacheTypedef]
            (fun () ->
              let (t', env') = lookup_typedef s !_scoped_env in
              NamedType (name, Some t') +>
              Ast_c.rewrap_typeC ty)
            (fun () -> ty)
      )
  | QualifiedType(typ, _name) -> ty

  | FieldType (t, _, _) -> type_unfold_one_step t env

  | TypeOfExpr e -> type_of_expr (fun t -> t) ty e
  | TypeOfType t -> type_unfold_one_step t env
  | AutoType -> ty
  | TemplateType _ -> ty in
  loop [] ty env

and type_of_expr extra ty e =
  (* hackish, but this is the only place where the
     difference between decltype and typeof matters *)
  let (qu, attr, ii) =
    let (qu, attr, (typeC, ii)) = ty in
    (qu, attr, List.hd ii) in
  let etype _ =
    match Type_c.get_opt_type e with
      Some t -> t
    | None -> ty in
  if str_of_info ii = "decltype"
  then
    (match Ast_c.unwrap_expr e with
      ParenExpr e ->
	(match Type_c.get_opt_type e with
	  Some t ->
	    (* position shouldn't matter because this is a type *)
	    let vp = ({str="";charpos=0;line=0;column=0;file=""},0) in
	    let ander =
	      { pinfo = FakeTok ("&",vp,Ast_c.After);
		cocci_tag = ref Ast_c.emptyAnnot;
		annots_tag = Token_annot.empty;
		comments_tag = ref Ast_c.emptyComments;
		danger = ref Ast_c.NoDanger;
	      } in
	    (qu, attr, (Pointer (extra t), [ander]))
	| None -> ty)
    | _ -> etype())
  else etype()

(* normalizer. can be seen as the opposite of the previous function as
 * we "fold" at least for the structUnion. Should return something that
 * Type_c.is_completed_fullType likes, something that makes it easier
 * for the programmer to work on, that has all the needed information
 * for most tasks.
 *)
let rec typedef_fix ty env =
  let rec loop seen ty env =
    match Ast_c.unwrap_typeC ty with
    | NoType  ->
	ty
    | BaseType x  ->
	ty
    | Pointer t ->
	Pointer (typedef_fix t env)  +> Ast_c.rewrap_typeC ty
    | Array (e, t) ->
	Array (e, typedef_fix t env) +> Ast_c.rewrap_typeC ty
    | StructUnion (su, sopt, optfinal, base_classes, fields) ->
      (* normalize, fold.
	 * todo? but what if correspond to a nested struct def ?
      *)
	Type_c.structdef_to_struct_name ty
    | FunctionType ft ->
	(FunctionType ft) (* todo ? *) +> Ast_c.rewrap_typeC ty
    | EnumDef  (ename, base, enumt) ->
	(EnumDef  (ename, base, enumt)) (* todo? *) +> Ast_c.rewrap_typeC ty
    | EnumName (key, id) ->
	(EnumName (key, id)) (* todo? *) +> Ast_c.rewrap_typeC ty
    | Decimal(l,p) ->
	(Decimal(l,p)) (* todo? *) +> Ast_c.rewrap_typeC ty

  (* we prefer StructUnionName to StructUnion when it comes to typed metavar *)
    | StructUnionName (su, s) ->
	ty

    | TypeName (name) ->
	ty

  (* keep the typename but complete with more information *)
    | NamedType (name, typ) ->
	let s = Ast_c.str_of_name name in
	(match typ with
	| Some _ ->
            pr2 ("typedef value already there:" ^ s);
            ty
	| None ->
            (try
              if !typedef_debug then pr2 "typedef_fix: lookup_typedef";
              let (t', env') = lookup_typedef s env in

          (* bugfix: termination bug if use env instead of env' below, because
             * can have some weird mutually recursive typedef which
             * each new type alias search for its mutual def.
	     * seen is an attempt to do better.
          *)
	      let fixed =
		if List.mem s seen
		then loop (s::seen) t' env
		else typedef_fix t' env' in
	      NamedType (name, Some fixed) +>
	      Ast_c.rewrap_typeC ty
            with Not_found ->
              let f = Ast_c.file_of_info (Ast_c.info_of_name name) in
              get_type_from_includes_cache
                f s [IC.CacheTypedef]
                (fun () ->
                   let (t', env') = lookup_typedef s !_scoped_env in
                   NamedType (name, Some t') +>
                   Ast_c.rewrap_typeC ty)
                (fun () -> ty)
              ))
    | QualifiedType (typ,_name) ->
    QualifiedType (typ,_name) +> Ast_c.rewrap_typeC ty
    | FieldType (t, a, b) ->
	FieldType (typedef_fix t env, a, b) +> Ast_c.rewrap_typeC ty

    | ParenType t ->
	ParenType (typedef_fix t env) +> Ast_c.rewrap_typeC ty

    | TypeOfExpr e -> type_of_expr (fun t -> typedef_fix t env) ty e

    | TypeOfType t ->
	typedef_fix t env
    | AutoType ->
	pr2_once ("Type_annoter: not handling unresolved auto");
	ty
    | TemplateType _ -> ty in
  loop [] ty env


(*****************************************************************************)
(* Helpers, part 1 *)
(*****************************************************************************)

let type_of_s2 s =
  (Lib.al_type (Parse_c.type_of_string s))
let type_of_s a =
  Common.profile_code "Type_c.type_of_s" (fun () -> type_of_s2 a)


(* pad: pb on:
 * /home/pad/software-os-src2/freebsd/contrib/ipfilter/netinet/ip_fil_freebsd.c
 * because in the code there is:
 *  	static iss_seq_off = 0;
 * which in the parser was generating a default int without a parse_info.
 * I now add a fake parse_info for such default int so no more failwith
 * normally.
 *)

let rec is_simple_expr expr =
  match Ast_c.unwrap_expr expr with
  (* todo? handle more special cases ? *)

  | Ident _ ->
      true
  | Constant (_)         ->
      true
  | Unary (op, e) ->
      true
  | Binary (e1, op, e2) ->
      true
  | Cast (t, e) ->
      true
  | ParenExpr (e) -> is_simple_expr e

  | _ -> false

(*****************************************************************************)
(* Typing rules *)
(*****************************************************************************)
(* now in type_c.ml *)



(*****************************************************************************)
(* (Semi) Globals, Julia's style *)
(*****************************************************************************)


(* memoise unnanoted var, to avoid too much warning messages *)
let _notyped_var = Hashtbl.create 101

let new_scope() =
  match !_scoped_env with
  | hd :: _ ->
      _scoped_env := { hd with level = succ hd.level; var_or_func = StringMap.empty; } :: !_scoped_env
  | [] ->
      _scoped_env := [ empty_frame ]
let del_scope() =
  _scoped_env := List.tl !_scoped_env

let do_in_new_scope f =
  begin
    new_scope();
    let res = f() in
    del_scope();
    res
  end

(* this is not functional at all, so why not use a hash table? *)
let add_in_scope namedef =
  let (current, older) = Common.uncons !_scoped_env in
  let current =
    match namedef with
      | VarOrFunc (s, typ) ->
	  {current with
	   var_or_func = StringMap.add s typ current.var_or_func}
      | TypeDef   (s, typ) ->
	  let v = typ, current.typedef, current.level in
	  let new_typedef : typedefs = { defs = StringMap.add s v current.typedef.defs } in
	  {current with typedef = new_typedef}
      | StructUnionNameDef (s, (su, typ)) ->
	  {current with
	   struct_union_name_def = StringMap.add s (su, typ) current.struct_union_name_def}
      | Macro (s, body) ->
	  {current with macro = StringMap.add s body current.macro}
      | EnumConstant (s, body) ->
	  {current with
	   enum_constant = StringMap.add s body current.enum_constant} in
  _scoped_env := current::older

(* ------------------------------------------------------------ *)

(* sort of hackish... *)
let islocal info =
  if List.length (!_scoped_env) = List.length !initial_env
  then Ast_c.NotLocalVar
  else Ast_c.LocalVar info

(* ------------------------------------------------------------ *)
(* the warning argument is here to allow some binding to overwrite an
 * existing one. With function, we first have the prototype and then the def,
 * and the def binding with the same string is not an error.
 *
 * todo?: but if we define two times the same function, then we will not
 * detect it :( it would require to make a diff between adding a binding
 * from a prototype and from a definition.
 *
 * opti: disabling the check_annotater flag have some important
 * performance benefit.
 *
 *)
let add_binding2 namedef warning =
  let (current_scope, _older_scope) = Common.uncons !_scoped_env in

  if !Flag_parsing_c.check_annotater then begin
    (match namedef with
    | VarOrFunc (s, typ) ->
        if Hashtbl.mem _notyped_var s
        then pr2 ("warning: found typing information for a variable that was" ^
                     "previously unknown:" ^ s);
    | _ -> ()
    );

    let (member, s) =
      let env = [current_scope] in
      (match namedef with
      | VarOrFunc (s, typ) ->
          (* XXX do not define member_env_lookup_var,
	     call "ignore (lookup_var ...)" and return
	     - false if a Not_found exception is raised;
	     - true otherwise *)
          member_env_lookup_var s env, s
      | TypeDef   (s, typ) ->
          member_env_lookup_typedef s env, s
      | StructUnionNameDef (s, (su, typ)) ->
          member_env_lookup_structunion (su, s) env, s
      | Macro (s, body) ->
          member_env_lookup_macro s env, s
      | EnumConstant (s, body) ->
          member_env_lookup_enum s env, s
      ) in

    if member && warning
    then pr2 ("Type_annoter: warning, " ^ s ^
                 " is already in current binding" ^ "\n" ^
                 " so there is a weird shadowing");
  end;
  add_in_scope namedef

let add_binding namedef warning =
  Common.profile_code "TAC.add_binding" (fun () -> add_binding2 namedef warning)



(*****************************************************************************)
(* Helpers, part 2 *)
(*****************************************************************************)

let lookup_opt_env lookupf s =
  Common.optionise (fun () ->
    lookupf s !_scoped_env
  )

let unwrap_unfold_env typ =
  Ast_c.unwrap_typeC
    (type_unfold_one_step typ !_scoped_env)

let typedef_fix a b =
  Common.profile_code "TAC.typedef_fix" (fun () -> typedef_fix a b)

let make_info_def_fix x =
  Type_c.make_info_def (typedef_fix x !_scoped_env)

let make_info_fix (typ, local) =
  Type_c.make_info ((typedef_fix typ !_scoped_env),local)


let make_info_def = Type_c.make_info_def

(*****************************************************************************)
(* Main typer code, put later in a visitor *)
(*****************************************************************************)

let annotater_expr_visitor_subpart = (fun (k,bigf) expr ->
  let ret_of_functiontype typ =
    let rec loop = function
    | FunctionType (ret, _) -> Some ret
    (* can be function pointer, C have an iso for that,
     * same pfn() syntax than regular function call. *)
    | Pointer typ | ParenType typ -> loop (unwrap_unfold_env typ)
    | _ -> None in
    loop (unwrap_unfold_env typ) in


  let ty =
    match Ast_c.unwrap_expr expr with

    (* -------------------------------------------------- *)
    (* todo: should analyse the 's' for int to know if unsigned or not *)
    | StringConstant (s,os,kind) -> make_info_def (type_of_s "char []")
    | Constant (String (s,kind)) -> make_info_def (type_of_s "char []")
    | Constant MultiString _  -> make_info_def (type_of_s "char []")
    | Constant (Char   (s,kind)) -> make_info_def (type_of_s "char")
    | Constant (Int (s,kind)) ->
	(* this seems really unpleasant, but perhaps the type needs to be set
	   up in some way that allows pretty printing *)
	make_info_def
	  (match kind with
	  (* matches limited by what is generated in lexer_c.mll *)
	    Si(Signed,CInt) -> type_of_s "int"
	  | Si(UnSigned,CInt) -> type_of_s "unsigned int"
	  | Si(Signed,CLong) -> type_of_s "long"
	  | Si(UnSigned,CLong) -> type_of_s "unsigned long"
	  | Si(Signed,CLongLong) -> type_of_s "long long"
	  | Si(UnSigned,CLongLong) -> type_of_s "unsigned long long"
	  | _ -> failwith "unexpected kind for constant")
    | Constant (Float (s,kind)) ->
	let names =
	  match kind with
	    Ast_c.CFloat -> ["float"]
	  | Ast_c.CDouble -> ["double"]
	  | Ast_c.CFloatComplex -> ["float";"complex"]
	  | Ast_c.CDoubleComplex -> ["double";"complex"]
	  | Ast_c.CLongDouble -> ["long";"double"]
	  | Ast_c.CLongDoubleComplex -> ["long";"double";"complex"]
	  | Ast_c.CUnknownComplex -> ["complex"] in
        let fake = Ast_c.fakeAfterInfo() in
        let iinull = List.map (fun s -> Ast_c.rewrap_str s fake) names in
        make_info_def (Ast_c.mk_ty (BaseType (FloatType kind)) iinull)
    | Constant (DecimalConst(s,n,p)) ->
        let fake = Ast_c.fakeAfterInfo() in
        let fake1 = Ast_c.rewrap_str "decimal" fake in
        let fake2 = Ast_c.rewrap_str "(" fake in
        let fake3 = Ast_c.rewrap_str "," fake in
        let fake4 = Ast_c.rewrap_str ")" fake in
        let iinull = [fake1;fake2;fake3;fake4] in
        let faken = Ast_c.rewrap_str n fake in
        let fakep = Ast_c.rewrap_str p fake in
	let sign = Ast_c.Si(Ast_c.Signed,CInt) in
	let n = mk_e(Ast_c.Constant(Ast_c.Int (n, sign))) [faken] in
	let p = mk_e(Ast_c.Constant(Ast_c.Int (p, sign))) [fakep] in
	make_info_def (Ast_c.mk_ty (Decimal(n,Some p)) iinull)


    (* -------------------------------------------------- *)
    (* note: could factorize this code with the code for Ident
     * and the other code for Funcall below. But as the Ident can be
     * a macro-func, I prefer to handle it separately. So
     * this rule can handle the macro-func, the Ident-rule can handle
     * the macro-var, and the other FunCall-rule the regular
     * function calls through fields.
     * Also as I don't want a warning on the Ident that are a FunCall,
     * easier to have a rule separate from the Ident rule.
     *)
    | FunCall (e1, args) ->
     (match Ast_c.unwrap_expr e1 with
     | Ident (ident) ->
        (* recurse *)
        args +> List.iter (fun (e,ii) ->
          (* could typecheck if arguments agree with prototype *)
          Visitor_c.vk_argument bigf e
        );
        let s = Ast_c.str_of_name ident in

	let get_return_type typ local =
          (* set type for ident *)
          let tyinfo = make_info_fix (typ, local) in
          Ast_c.set_type_expr e1 tyinfo;

          (match ret_of_functiontype typ with
          | Some ret -> make_info_def ret
          | None -> Type_c.noTypeHere) in

        (match lookup_opt_env lookup_var s with
        | Some (typ,local) -> get_return_type typ local
        | None  ->

            (match lookup_opt_env lookup_macro s with
            | Some (defkind, defval) ->
                (match defkind, defval with
                | DefineFunc _, DefineExpr e ->
                    let rettype = Ast_c.get_onlytype_expr e in

                    (* todo: could also set type for ident ?
                       have return type and at least type of concrete
                       parameters so can generate a fake FunctionType
                    *)
                    let macrotype_opt =
                      Type_c.fake_function_type rettype args
                    in

                    macrotype_opt +> Common.do_option (fun t ->
                      pr2 ("Type_annotater: generate fake function type" ^
                              "for macro: " ^ s);
                      let tyinfo = make_info_def_fix t in
                      Ast_c.set_type_expr e1 tyinfo;
                    );

                    Ast_c.get_type_expr e
                | DefineVar, _ ->
                    pr2 ("Type_annoter: not a macro-func: " ^ s);
                    Type_c.noTypeHere
                | Undef, _ ->
                    pr2 ("Type_annoter: not a macro-func: " ^ s);
                    Type_c.noTypeHere
                | DefineFunc _, _ ->
                    (* normally the FunCall case should have caught it *)
                    pr2 ("Type_annoter: not a macro-func-expr: " ^ s);
                    Type_c.noTypeHere
                )
            | None ->
                let f =
                  Ast_c.file_of_info
                    (Ast_c.info_of_name ident) in
                get_type_from_includes_cache
                  f s [IC.CacheVarFunc]
                  (fun () ->
                     match lookup_opt_env lookup_var s with
                       Some (typ, local) -> get_return_type typ local
                     | None -> Type_c.noTypeHere)
                  (fun () -> Type_c.noTypeHere)
            )
        )


      | _e ->
        k expr;

        (Ast_c.get_type_expr e1) +> Type_c.do_with_type (fun typ ->
          (* copy paste of above *)
          (match ret_of_functiontype typ with
          | Some ret -> make_info_def ret
          | None -> Type_c.noTypeHere
          )
        )
     )


    (* -------------------------------------------------- *)
    | Ident (ident) ->
        let s = Ast_c.str_of_name ident in
        (match lookup_opt_env lookup_var s with
        | Some (typ,local) -> make_info_fix (typ,local)
        | None  ->
            (match lookup_opt_env lookup_macro s with
            | Some (defkind, defval) ->
                (match defkind, defval with
                | DefineVar, DefineExpr e ->
                    Ast_c.get_type_expr e
                | DefineVar, _ ->
                    pr2 ("Type_annoter: not a expression: " ^ s);
                    Type_c.noTypeHere
                | DefineFunc _, _ ->
                    (* normally the FunCall case should have catch it *)
                    pr2 ("Type_annoter: not a macro-var: " ^ s);
                    Type_c.noTypeHere
                | Undef, _ ->
                    pr2 ("Type_annoter: not a expression: " ^ s);
                    Type_c.noTypeHere
                )
            | None ->
                (match lookup_opt_env lookup_enum s with
                | Some _ ->
                    make_info_def (type_of_s "int")
                | None ->
                    let f = Ast_c.file_of_info (Ast_c.info_of_name ident) in
                    let failure_fn =
                      (fun () ->
                         if not (s =~ "[A-Z_]+") (* if macro then no warning *)
                         then
                           if !Flag_parsing_c.check_annotater
                           then
                             if not (Hashtbl.mem _notyped_var s)
                             then
                               begin
                                 pr2
                                   ("Type_annoter: no type found for: " ^ s);
                                 Hashtbl.add _notyped_var s true;
                               end
                             else ()
                           else pr2 ("Type_annoter: no type found for: " ^ s);
                         Type_c.noTypeHere) in
                    get_type_from_includes_cache
                      f s [IC.CacheEnumConst;IC.CacheVarFunc]
                      (fun () ->
                         match lookup_opt_env lookup_enum s with
                           Some _ -> make_info_def (type_of_s "int")
                         | None ->
                             (match lookup_opt_env lookup_var s with
                                Some (typ,local) -> make_info_fix (typ,local)
                              | None -> failure_fn ()))
                      failure_fn
            )
        )
    )

    (* -------------------------------------------------- *)
    (* C isomorphism on type on array and pointers *)
    | Unary (e, DeRef)
    | ArrayAccess (e, _) ->
        k expr; (* recurse to set the types-ref of sub expressions *)

        (Ast_c.get_type_expr e) +> Type_c.do_with_type (fun t ->
          (* todo: maybe not good env !! *)
          match unwrap_unfold_env t with
          | Pointer x
          | Array (_, x) ->
              make_info_def_fix x
          | _ -> Type_c.noTypeHere

        )

    | Unary (e, GetRef) ->
        k expr; (* recurse to set the types-ref of sub expressions *)

	let inherited_fn tq1 ((tq2,ii),attr,ty) = (* should we union the attrs? *)
	  let cst = tq1.Ast_c.const || tq2.Ast_c.const in
	  let vol = tq1.Ast_c.volatile || tq2.Ast_c.volatile in
	  let res = tq1.Ast_c.restrict || tq2.Ast_c.restrict in
	  (({Ast_c.const=cst;Ast_c.volatile=vol;Ast_c.restrict=res},ii),attr,ty) in
	let rec inherited e =
	  match Ast_c.unwrap_expr e with
	    RecordAccess (e, _) ->
	      (match Ast_c.get_onlytype_expr e with
		Some ((tq1,_),_,_) -> inherited_fn tq1
	      | None -> (fun x -> x))
	  | RecordPtAccess (e, _) ->
	      (match Ast_c.get_onlytype_expr e with
		Some(_,_,(Ast_c.Pointer ((tq1,_),_,_),_)) -> inherited_fn tq1
	      | Some t -> (fun x -> x)
	      | None -> (fun x -> x))
	  | ArrayAccess (e, _) -> inherited e
	  | _ -> fun x -> x in

        (Ast_c.get_type_expr e) +> Type_c.do_with_type (fun t ->
          (* must generate an element so that '=' can be used
           * to compare type ?
           *)
	  let ft =
	    let is_fn_ar = (* & has no impact for fn or array *)
	      match Ast_c.unwrap_typeC t with
		ParenType pt ->
		  (match Ast_c.unwrap_typeC pt with
		    Pointer t ->
		      (match Ast_c.unwrap_typeC t with
			FunctionType (returnt, paramst) -> true
		      | _ -> false)
		  | _ -> false)
	      | Array _ -> true
	      | _ -> false in
	    if is_fn_ar
	    then t
	    else
	      (* NoPos because a type generated on the fly *)
	      let fake = Ast_c.fakeAfterInfoNoPos() in
              let fake = Ast_c.rewrap_str "*" fake in
              Ast_c.mk_ty (Pointer ((inherited e) t)) [fake] in
          make_info_def_fix ft
        )

    (* -------------------------------------------------- *)
    (* fields *)
    | RecordAccess  (e, namefld)
    | RecordPtAccess (e, namefld) as x ->
        let fld = Ast_c.str_of_name namefld in

        k expr; (* recurse to set the types-ref of sub expressions *)

        (Ast_c.get_type_expr e) +> Type_c.do_with_type (fun t ->

          let topt =
            match x with
            | RecordAccess _ -> Some t
            | RecordPtAccess _ ->
                (match unwrap_unfold_env t with
                | Pointer (t) -> Some t
                | _ -> None
                )
            | _ -> raise (Impossible 159)

          in
          (match topt with
          | None -> Type_c.noTypeHere
          | Some t ->
              match unwrap_unfold_env t with
              | StructUnion (su, sopt, optfinal, base_classes, fields) ->
                  (try
                      (* todo: which env ? *)
                      make_info_def_fix
                        (Type_c.type_field fld (su, fields))
                    with
                    | Not_found ->
                        pr2 (spf
                                "TYPE-ERROR: field '%s' does not belong in struct %s"
                                fld (match sopt with Some s -> s |_ -> "<anon>"));
                        Type_c.noTypeHere
                    | Multi_found ->
                        pr2 "TAC:MultiFound";
                        Type_c.noTypeHere
                  )
              | _ ->
                let s = Ast_c.str_of_name namefld in
                let f = Ast_c.file_of_info (Ast_c.info_of_name namefld) in
                let ret_typ =
                  (match Ast_c.unwrap_typeC t with
                    Ast_c.StructUnionName(su, sname) ->
                      get_type_from_includes_cache
                        f s [IC.CacheField sname]
                        (fun () ->
                           try
                             let ((su,fields),ii) =
                               lookup_structunion (su, sname) !_scoped_env in
                               try
                                  make_info_def_fix
                                    (Type_c.type_field fld (su, fields))
                                with _ -> Type_c.noTypeHere
                           with Not_found -> Type_c.noTypeHere)
                        (fun () -> Type_c.noTypeHere)
                  | _ -> Type_c.noTypeHere)
                in ret_typ
          )
        )

    | QualifiedAccess(Some ty,_) ->
        k expr;
        make_info_def_fix(Lib.al_type ty)
    | QualifiedAccess(None,_) -> Type_c.noTypeHere
    (* -------------------------------------------------- *)
    | Cast (t, e) ->
        k expr;
        (* todo: if infer, can "push" info ? add_types_expr [t] e ? *)
        make_info_def_fix (Lib.al_type t)

    (* todo? lub, hmm maybe not, cos type must be e1 *)
    | Assignment (e1, op, e2) ->
        k expr;
        (* value of an assignment is the value of the RHS expression, but its
           type is the type of the lhs expression.  Use the rhs exp if no
	   information is available *)
        (match Ast_c.get_type_expr e1 with
	  (None,_) -> Ast_c.get_type_expr e2
	| (Some ty,t) -> (Some ty,t))
    | Sequence (e1, e2) ->
        k expr;
        Ast_c.get_type_expr e2

    | Binary (e1, ((Logical _),_), e2) ->
        k expr;
        make_info_def (type_of_s "int")

    (* todo: lub *)
    | Binary (e1, (Arith op, _), e2) ->
        k expr;
        Type_c.lub op (Type_c.get_opt_type e1) (Type_c.get_opt_type e2)

    | CondExpr (cond, e1opt, e2) ->
        k expr;
        Ast_c.get_type_expr e2


    | ParenExpr e ->
        k expr;
        Ast_c.get_type_expr e

    | Infix (e, op)  | Postfix (e, op) ->
        k expr;
        Ast_c.get_type_expr e

    (* pad: julia wrote this ? *)
    | Unary (e, UnPlus) ->
        k expr; (* recurse to set the types-ref of sub expressions *)
	(* No type inference.  If one cares about being int, one probably
	   cares about what kind of int too *)
        Ast_c.get_type_expr e

    | Unary (e, UnMinus) ->
        k expr; (* recurse to set the types-ref of sub expressions *)
	(* No type inference.  If one cares about being int, one probably
	   cares about what kind of int too *)
        Ast_c.get_type_expr e

    | SizeOfType _|SizeOfExpr _ ->
        k expr; (* recurse to set the types-ref of sub expressions *)
        make_info_def (type_of_s "size_t")

    | Constructor (ft, ini) ->
        k expr; (* recurse to set the types-ref of sub expressions *)
        make_info_def (Lib.al_type ft)

    | Unary (e, Not) ->
        k expr; (* recurse to set the types-ref of sub expressions *)
	(* the result of ! is always 0 or 1, not the argument type *)
        make_info_def (type_of_s "int")
    | Unary (e, Tilde) ->
        k expr; (* recurse to set the types-ref of sub expressions *)
        Ast_c.get_type_expr e

    (* -------------------------------------------------- *)
    (* todo *)
    | Unary (_, GetRefLabel) ->
        k expr; (* recurse to set the types-ref of sub expressions *)
        pr2_once "Type annotater:not handling GetRefLabel";
        Type_c.noTypeHere
          (* todo *)
    | StatementExpr _ ->
        k expr; (* recurse to set the types-ref of sub expressions *)
        pr2_once "Type annotater:not handling StatementExpr";
        Type_c.noTypeHere
          (*
            | _ -> k expr; Type_c.noTypeHere
          *)

    | New (_, ty, _) ->
	k expr;
	pr2_once "Type annotater:not handling New";
	Type_c.noTypeHere (* TODO *)

    | Delete (box,e) ->
	k expr;
	pr2_once "Type annotater:not handling Delete";
	Type_c.noTypeHere (* TODO *)

    | TemplateInst(name,args) ->
	k expr;
	Type_c.noTypeHere
    
    (* TODO: Make a proper tuple type *)
    | TupleExpr(args) ->
    k expr;
    Type_c.noTypeHere

    | Defined _ ->
	make_info_def (type_of_s "int")

  in
  Ast_c.set_type_expr expr ty

)


(*****************************************************************************)
(* Visitor *)
(*****************************************************************************)

(* Processing includes that were added after a cpp_ast_c makes the
 * type annotater quite slow, especially when the depth of cpp_ast_c is
 * big. But for such includes the only thing we really want is to modify
 * the environment to have enough type information. We don't need
 * to type the expressions inside those includes (they will be typed
 * when we process the include file directly). Here the goal is
 * to not recurse.
 *
 * Note that as usually header files contain mostly structure
 * definitions and defines, that means we still have to do lots of work.
 * We only win on function definition bodies, but usually header files
 * have just prototypes, or inline function definitions which anyway have
 * usually a small body. But still, we win. It also makes clearer
 * that when processing include as we just need the environment, the caller
 * of this module can do further optimisations such as memorising the
 * state of the environment after each header files.
 *
 *
 * For sparse its makes the annotating speed goes from 9s to 4s
 * For Linux the speedup is even better, from ??? to ???.
 *
 * Because There would be some copy paste with annotate_program, it is
 * better to factorize code hence the just_add_in_env parameter below.
 *
 * todo? alternative optimization for the include problem:
 *  - processing all headers files one time and construct big env
 *  - use hashtbl for env (but apparently not biggest problem)
 *)

let rec visit_toplevel ~just_add_in_env ~depth elem =
  let need_annotate_body = not just_add_in_env in

  let bigf = { Visitor_c.default_visitor_c with

    (* ------------------------------------------------------------ *)
    Visitor_c.kcppdirective = (fun (k, bigf) directive ->
      match directive with
      (* do error messages for type annotater only for the real body of the
       * file, not inside include.
       *)
      | UsingNamespace _ -> ()
      | Include {i_content = opt} ->
          opt +> Common.do_option (fun (filename, program) ->
            Common.save_excursion Flag_parsing_c.verbose_type (fun () ->
              Flag_parsing_c.verbose_type := false;

              (* old: Visitor_c.vk_program bigf program;
               * opti: set the just_add_in_env
               *)
              program +> List.iter (fun elem ->
                visit_toplevel ~just_add_in_env:true ~depth:(depth+1) elem
              )
            )
          )

      | Define ((s,ii), (defkind, defval)) ->


          (* even if we are in a just_add_in_env phase, such as when
           * we process include, as opposed to the body of functions,
           * with macros we still to type the body of the macro as
           * the macro has no type and so we infer its type from its
           * body (and one day later maybe from its use).
           *)
	  do_in_new_scope (fun () ->
	    (* prevent macro-declared variables from leaking out *)
	    (match defkind with
	      DefineFunc (params,ii) ->
		List.iter
		  (function ((id,ii),commaii) ->
		    let local = Ast_c.LocalVar (List.hd ii).pinfo in
		    let bind =
		      VarOrFunc (id,(Lib.al_type (mk_ty NoType []),local)) in
		    add_binding bind true)
		  params
	    | _ -> ());
	    match defval with
            (* can try to optimize and recurse only when the define body
             * is simple ?
             *)

            | DefineExpr expr ->
		if is_simple_expr expr
                (* even if not need_annotate_body, still recurse*)
		then k directive
		else
                  if need_annotate_body
                  then k directive
	    | _ ->
		if need_annotate_body
		then k directive);

          add_binding (Macro (s, (defkind, defval) )) true;

      |	Pragma((name,rest), ii) -> ()

      | OtherDirective _ | UsingTypename _ | UsingMember _ -> ()
    );

    (* ------------------------------------------------------------ *)
    (* main typer code *)
    (* ------------------------------------------------------------ *)
    Visitor_c.kexpr = annotater_expr_visitor_subpart;

    (* ------------------------------------------------------------ *)
    Visitor_c.kstatement = (fun (k, bigf) st ->
      match Ast_c.unwrap_st st with
      | Compound statxs -> do_in_new_scope (fun () -> k st);
      | _ -> k st
    );
    (* ------------------------------------------------------------ *)
    Visitor_c.kdecl = (fun (k, bigf) d ->
      (match d with
      | (DeclList ((xs, has_ender), ii)) ->
          xs +> List.iter (fun ({v_namei = var; v_type = t;
                                 v_storage = sto; v_local = local} as x
                                   , iicomma) ->

            (* to add possible definition in type found in Decl *)
            Visitor_c.vk_type bigf t;


	    let local =
	      match (sto,local) with
	      | (_,Ast_c.NotLocalDecl) -> Ast_c.NotLocalVar
	      |	((Ast_c.Sto Ast_c.Static, _, _), Ast_c.LocalDecl) ->
		  (match Ast_c.info_of_type t with
		    (* if there is no info about the type it must not be
		       present, so we don't know what the variable is *)
		    None -> Ast_c.NotLocalVar
		  | Some ii -> Ast_c.StaticLocalVar ii)
	      |	(_,Ast_c.LocalDecl) ->
		  (match Ast_c.info_of_type t with
		    (* if there is no info about the type it must not be
		       present, so we don't know what the variable is *)
		    None -> Ast_c.NotLocalVar
		  | Some ii -> Ast_c.LocalVar ii)
            in
            var +> Common.do_option (fun (name, iniopt) ->
              let s = Ast_c.str_of_name name in

	      let t =
		match Ast_c.unwrap_typeC t with
		| Ast_c.Decimal (len,None) ->
		    let newp =
		      Ast_c.rewrap_expr len
			 (Ast_c.Constant
			    (Ast_c.Int
			       ("0",Ast_c.Si(Ast_c.Signed,Ast_c.CInt)))) in
		    Ast_c.rewrap_typeC t (Ast_c.Decimal (len,Some newp))
		| _ -> t in


              match sto with
              | StoTypedef, _inline, _align ->
                  add_binding (TypeDef (s,Lib.al_type t)) true;
              | _ ->
                  add_binding (VarOrFunc (s, (Lib.al_type t, local))) true;

                  x.v_type_bis :=
                    Some (typedef_fix (Lib.al_type t) !_scoped_env);

                  if need_annotate_body then begin
                    (* int x = sizeof(x) is legal so need process ini *)
		    match iniopt with
		      Ast_c.NoInit -> ()
		    | Ast_c.ValInit(init,iini) -> Visitor_c.vk_ini bigf init
                  end
            );
          );
      | MacroDecl _ | MacroDeclInit _ ->
          if need_annotate_body
          then k d
      );

    );

    (* ------------------------------------------------------------ *)
    Visitor_c.ktype = (fun (k, bigf) typ ->
      (* bugfix: have a 'Lib.al_type typ' before, but because we can
       * have enum with possible expression, we don't want to change
       * the ref of abstract-lined types, but the real one, so
       * don't al_type here
       *)
      let (_q, _attr, tbis) = typ in
      match Ast_c.unwrap_typeC typ with
      | StructUnion  (su, Some s, optfinal, base_classes, structType) ->
          let structType' = Lib.al_fields structType in
          let ii = Ast_c.get_ii_typeC_take_care tbis in
          let ii' = Lib.al_ii ii in
          add_binding (StructUnionNameDef (s, ((su, structType'),ii')))  true;

          if need_annotate_body
          then do_in_new_scope (fun () -> k typ) (* todo: restrict ? new scope so use do_in_scope ? *)

      | EnumDef (sopt, base, enums) ->

          enums +> List.iter (fun ((name, eopt), iicomma) ->

            let s = Ast_c.str_of_name name in

            if need_annotate_body
            then eopt +> Common.do_option (fun (ieq, e) ->
              Visitor_c.vk_expr bigf e
            );
            add_binding (EnumConstant (s, sopt)) true;
          );


      (* TODO: if have a NamedType, then maybe can fill the option
       * information.
       *)
      | _ ->
          if need_annotate_body
          then k typ

    );

    (* ------------------------------------------------------------ *)
    Visitor_c.ktoplevel = (fun (k, bigf) elem ->
      match elem with
      | Definition def ->
          let {f_name = name;
               f_type = ((returnt, (paramst, b)) as ftyp);
               f_storage = sto;
               f_body = statxs;
               f_old_c_style = oldstyle;
               },ii
            = def
          in
          let (i1, i2) =
            match ii with
	      (* what is iifunc1?  it should be a type.  jll
               * pad: it's the '(' in the function definition. The
               * return type is part of f_type.
               *)
            | iifunc1::iifunc2::ibrace1::ibrace2::ifakestart::isto ->
                iifunc1, iifunc2
            | _ -> raise (Impossible 160)
          in
          let funcs = Ast_c.str_of_name name in

          (match oldstyle with
          | None ->
              let fake = Ast_c.fakeAfterInfo() in
              let fakea = Ast_c.rewrap_str "*" fake in
              let fakeopar = Ast_c.rewrap_str "(" fake in
              let fakecpar = Ast_c.rewrap_str ")" fake in

              let typ' = Lib.al_type (Ast_c.mk_ty (ParenType (Ast_c.mk_ty
                (Pointer ( Ast_c.mk_ty (FunctionType ftyp) [i1;i2])) [fakea])) [fakeopar;fakecpar]) in

              add_binding (VarOrFunc (funcs, (typ',islocal i1.Ast_c.pinfo)))
                false;

              if need_annotate_body then
                do_in_new_scope (fun () ->
                  paramst +> List.iter (fun ({p_namei= nameopt; p_type= t},_)->
                    match nameopt with
                    | Some name ->
                        let s = Ast_c.str_of_name name in
		        let local =
			  (match Ast_c.info_of_type t with
			    (* if there is no info about the type it must
			       not be present, so we don't know what the
			       variable is *)
			    None -> Ast_c.NotLocalVar
			  | Some ii -> Ast_c.LocalVar ii)
			in
		        add_binding (VarOrFunc (s,(Lib.al_type t,local))) true
                    | None ->
                    pr2 "no type, certainly because Void type ?"
                  );
                  (* recurse *)
                  k elem
                );
          | Some oldstyle ->
              (* generate regular function type *)

              pr2 "TODO generate type for function";
              (* add bindings *)
              if need_annotate_body then
                do_in_new_scope (fun () ->
                  (* recurse. should naturally call the kdecl visitor and
                   * add binding
                   *)
                  k elem;
                );

          );
      | CppTop x ->
          (match x with
          | Define ((s,ii), (DefineVar, DefineType t)) ->
              add_binding (TypeDef (s,Lib.al_type t)) true;
          | _ -> k elem
          )

      | Declaration _



      | IfdefTop _
      | MacroTop _
      | EmptyDef _
      | NotParsedCorrectly _
      | FinalDef _
      | Namespace _
      | TemplateDefinition _
          ->
          k elem
    );
  }
  in
  (if just_add_in_env
  then
    if depth > 1
    then Visitor_c.vk_toplevel bigf elem
    else
      Common.profile_code "TAC.annotate_only_included" (fun () ->
        Visitor_c.vk_toplevel bigf elem
      )
  else Visitor_c.vk_toplevel bigf elem);
  Stdcompat.Hashtbl.reset _notyped_var


(*****************************************************************************)
(* Entry point *)
(*****************************************************************************)
(* catch all the decl to grow the environment *)


let (annotate_program2 :
  environment -> toplevel list -> (toplevel * environment Common.pair) list) =
 fun env prog ->

  (* globals (re)initialialisation *)
  _scoped_env := env;

   let res =
     prog +> List.map (fun elem ->
       let beforeenv = !_scoped_env in
       visit_toplevel ~just_add_in_env:false ~depth:0 elem;
       let afterenv = !_scoped_env in
       (elem, (beforeenv, afterenv))) in
  Stdcompat.Hashtbl.reset _notyped_var;
   res



(*****************************************************************************)
(* Annotate test *)
(*****************************************************************************)

(* julia: for coccinelle *)
let annotate_test_expressions prog =
  let rec propagate_test e =
    let ((e_term,info),_) = e in
    let (ty,_) = !info in
    info := (ty,Test);
    match e_term with
      Binary(e1,(Logical AndLog,_),e2)
    | Binary(e1,(Logical OrLog,_),e2) -> propagate_test e1; propagate_test e2
    | Unary(e1,Not) -> propagate_test e1
    | ParenExpr(e) -> propagate_test e
    | FunCall(e,args) -> (* not very nice, but so painful otherwise *)
	(match (unwrap e,args) with
	  ((Ident(i),_),[(Left a,_)]) ->
	    let nm = str_of_name i in
	    if List.mem nm ["likely";"unlikely"]
	    then propagate_test a
	    else ()
	| _ -> ())
    | _ -> () in

  let bigf = { Visitor_c.default_visitor_c with
    Visitor_c.kexpr = (fun (k,bigf) expr ->
      (match unwrap_expr expr with
	CondExpr(e,_,_) -> propagate_test e
      |	Binary(e1,(Logical AndLog,_),e2)
      | Binary(e1,(Logical OrLog,_),e2) -> propagate_test e1; propagate_test e2
      | Unary(e1,Not) -> propagate_test e1
      | _ -> ()
      );
      k expr
    );
    Visitor_c.kstatement = (fun (k, bigf) st ->
      match unwrap_st st with
	Selection(s) ->
	  (match s with If(e1,s1,s2) -> propagate_test e1 | _ -> ());
	  k st;
      |	Iteration(i) ->
	  (match i with
	    While(WhileExp (e),s) -> propagate_test e
	  | While(WhileDecl (DeclList dl),s) ->
              (match unwrap dl with
                ([x], has_ender) ->
                  (match (unwrap2 x).v_namei with
                    Some (n,ValInit z) ->
                      (match unwrap (unwrap z ) with
                        InitExpr e -> propagate_test e
                      | _ -> ())
                  | _ -> ())
              | _ -> ())
	  | DoWhile(s,e) -> propagate_test e
	  | For(ForExp(_,(Some e,_),_),_) -> propagate_test e
	  | For(ForDecl(_,(Some e,_),_),_) -> propagate_test e
	  | _ -> ());
	  k st
      | _ -> k st
    )
  } in
  (prog +> List.iter (fun elem ->
    Visitor_c.vk_toplevel bigf elem
  ))



(*****************************************************************************)
(* Annotate types *)
(*****************************************************************************)
let annotate_program env prog =
  Common.profile_code "TAC.annotate_program"
    (fun () ->
      let res = annotate_program2 env prog in
      annotate_test_expressions prog;
      res
    )
