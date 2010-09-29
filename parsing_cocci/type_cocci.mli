type inherited = bool (* true if inherited *)
type keep_binding = Unitary (* need no info *)
  | Nonunitary (* need an env entry *) | Saved (* need a witness *)

type typeC = 
    ConstVol        of const_vol * typeC
  | BaseType        of baseType * sign option
  | Pointer         of typeC
  | FunctionPointer of typeC (* only return type *)
  | Array           of typeC (* drop size info *)
  | StructUnionName of structUnion * bool (* true if type metavar *) * string
  | TypeName        of string
  | MetaType        of (string * string) * keep_binding * inherited
  | Unknown (* for metavariables of type expression *^* *)

and tagged_string = string
     
and baseType = VoidType | CharType | ShortType | IntType | DoubleType
| FloatType | LongType | BoolType

and structUnion = Struct | Union

and sign = Signed | Unsigned

and const_vol = Const | Volatile

val typeC : typeC -> unit

val compatible : typeC -> typeC option -> bool
