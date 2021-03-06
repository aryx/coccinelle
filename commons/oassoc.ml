open Ocollection

(* assoc, also called map or dictionnary *)
class virtual ['a,'b] oassoc = 
object(o: 'o)
  inherit ['a * 'b] ocollection
  
  method virtual assoc: 'a -> 'b
  method virtual delkey: 'a -> 'o
 
  (* pre: must be in *)
  method replkey: ('a * 'b) -> 'o = 
    fun (k,v) -> o#add (k,v) 

  (* pre: must not be in *)
  (* method add: ('a * 'b) -> 'o = *)

  (* method virtual keys: 'a oset *)

  method find: 'a -> 'b = fun k -> 
    o#assoc k

  method haskey: 'a -> bool = fun k -> 
    try (ignore(o#assoc k); true) 
    with Not_found -> false
 
  method apply: 'a -> ('b -> 'b) -> 'o = fun k f -> 
    let old = o#assoc k in 
    o#replkey (k, f old)

  (* apply default, assoc_default, take in class parameters a default value *)
  method apply_with_default: 'a -> ('b -> 'b) -> (unit -> 'b) -> 'o = 
    fun k f default -> 
      let old = 
        try o#assoc k
        with Not_found -> default ()
      in
      o#replkey (k, f old)

end
