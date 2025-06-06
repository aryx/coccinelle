# Fields and methods exposed via cocci object

## cocci.cocci_file

File name of the cocci file currently processed.

## cocci.exit()

Sets "exited" flag, that will stop the transformation of the current
file at the end of the execution of the Python script.

Example: ctests/exitp.cocci

## cocci.include_match(state)

If a python rule is running, it has matched. If the match should be
removed from consideration, this can be called with `state` set to
`False`.

Example: ctests/incpos.cocci

## cocci.has_env_binding(rule, name)

Returns `true` if the meta-variable `name` is bound in the rule
`rule`.

## cocci.add_pending_instance(files, virtual_rules, virtual_identifiers, extend_virtual_ids)

Internal function for the method iteration.register().

## cocci.make_ident(id)

Converts the string `id` to a C identifier.
(Equivalent to Coccilib.make_ident in OCaml.)

Example: ctests/python_mdecl.cocci

## cocci.make_expr(expr)

Converts the thing `expr` to a C expression.
(Equivalent to Coccilib.make_expr in OCaml.)

Example: ctests/python_mdecl.cocci

## cocci.make_stmt(phrase)

Parses the string `phrase` as a C statement and returns the statement.
(Equivalent to Coccilib.make_stmt in OCaml.)

Example: ctests/python_mdecl.cocci

## cocci.make_stmt_with_env(env, phrase)

Parses the string `env` as a C declaration and parses the string `phrase`
as a C statement in this environment and returns the statement.

Example: ctests/python_mdecl.cocci

## cocci.make_type(type)

Parses the string `type` as a C type and returns the type.

## cocci.make_pragmainfo(s)

Creates a representation of the string `s` suitable for storing in a
pragmainfo metavariable.  Coccinelle represents a pragma as, essentially,
\#pragma name pragmainfo where pragmainfo is an arbitrary sequence of tokens.

## cocci.make_listlen(len)

Converts the integer `len` to a list length.

## cocci.make_position(fl, fn, startl, startc, endl, endc)

Returns a position with filename `fl` (a string), element `fn` (a string),
starting at line `startl`, column `startc` (integers), and
ending at line `endl`, column `endc` (integers).
(Equivalent to Coccilib.make_position in OCaml.)

Example: ctests/python_mdeclp.cocci

## cocci.files()

Returns the list of current file names (as strings).
(Equivalent to Coccilib.files in OCaml.)

Example: ctests/scope_id_1_python.cocci
