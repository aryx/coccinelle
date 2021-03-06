open Common

open Bdb

open Oassoc

(* !!take care!!: this class does side effect, not a pure oassoc 
 *
 * The fv/unv are to give the opportunity to translate the value from
 * the dbm, before marshalling. Cf oassocdbm.mli for more about this.
 * 
 * Quite similar to oassocdbm.ml. New: Take transact argument.
 *)
class ['a,'b] oassoc_btree db namedb transact (*fkey unkey*) fv unv = 
let namedb = if namedb = "" then "" else "(" ^ namedb ^ ")" in
object(o)
  inherit ['a,'b] oassoc
    
  val data = db
    
  method empty = 
    raise Todo

  method private add2 (k,v) = 
    (* pr2 (fkey k); *)
    (* pr2 (debugv v); *)

    (* try Db.del data None 
       (Marshal.to_string k []) [] 
       with Not_found -> ());
    *)
    let k' = Marshal.to_string k [] in
    let v' = Marshal.to_string (fv v) [Marshal.Closures] in (* still clos? *)
    Db.put data (transact()) k' v' []; 
    (* minsky wrapper ?  Db.put data ~txn:(transact()) ~key:k' ~data:v' *)
    o
  method add x = 
    Common.profile_code ("Btree.add" ^ namedb) (fun () -> o#add2 x)

  (* bugfix: if not tail call (because of a try for instance), 
   * then strange behaviour in native mode 
   *)
  method private iter2 f = 
    let dbc = Cursor.db_cursor db (transact()) [] in
    (* minsky wrapper? Cursor.create ~writecursor:false ~txn:(transact()) db *)
    let rec aux dbc = 
      if
	(try 
	    let a = Cursor.dbc_get dbc [Cursor.DB_NEXT] in
            (* minsky ? Cursor.get dbc Cursor.NEXT [] *)
	    let key  = (* unkey *) Marshal.from_string (fst a) 0 in 
	    let valu = unv (Marshal.from_string (snd a) 0) in
	    f (key, valu);
            true
	 with Failure "ending" -> false
        ) 
      then aux dbc
      else ()
        
    in 
    aux dbc; 
    Cursor.dbc_close dbc (* minsky Cursor.close dbc *)

  method iter x = 
    Common.profile_code ("Btree.iter" ^ namedb) (fun () -> o#iter2 x)

  method view = 
    raise Todo


  
  method private length2 = 
    let dbc = Cursor.db_cursor db (transact()) [] in

    let count = ref 0 in
    let rec aux dbc = 
      if (
        try 
	  let _a = Cursor.dbc_get dbc [Cursor.DB_NEXT] in
          incr count;
          true
	with Failure "ending" -> false 
      )
      then aux dbc
      else ()

    in 
    aux dbc; 
    Cursor.dbc_close dbc; 
    !count 

  method length = 
    Common.profile_code ("Btree.length" ^ namedb) (fun () -> o#length2)


  method del (k,v) = raise Todo
  method mem e = raise Todo
  method null = raise Todo

  method private assoc2 k = 
    try 
      let k' = Marshal.to_string k [] in
      let vget = Db.get data (transact()) k' [] in
      (* minsky ? Db.get data ~txn:(transact() *)
      unv (Marshal.from_string vget  0)
    with Not_found -> 
      log3 ("pb assoc with k = " ^ (Dumper.dump k)); 
      raise Not_found
  method assoc x = 
    Common.profile_code ("Btree.assoc" ^ namedb) (fun () -> o#assoc2 x)

  method private delkey2 k = 
    let k' = Marshal.to_string k [] in
    Db.del data (transact()) k'  []; 
    o
  method delkey x = 
    Common.profile_code ("Btree.delkey" ^ namedb) (fun () -> o#delkey2 x)

end	
