:- use_module(library(lists)).
:- use_module(library(si)).

:- module('$toplevel', ['$entrypoint'/1, consult/1, use_module/1, use_module/2]).

%% Note: due to the way we run this, the entrypoint rule cannot have multiple
%%       rule heads (we're setting up the heap, and it's consumed once?).
%% TODO - Is this true?
%%      - Handing over to the REPL doesn't work.
'$entrypoint'(Args) :-
  '$run'(Args).

%% first arg is executable name
'$run'([_ | Args]) :-
    member(V, ['-v', '--version']),
    member(V, Args),
    write('version: todo\n'). %% todo: print actual version
'$run'([_ | Args]) :-
    '$run'(Args, [], []).

'$run'([G, Goal | Args], Mods, Goals) :-
    member(G, ['-g', '--goal']),
    '$run'(Args, Mods, [Goal | Goals]).
'$run'([Mod | Args], Mods, Goals) :-
    '$run'(Args, [Mod | Mods], Goals).
'$run'([], Mods0, []) :- %% no goals, run repl
    reverse(Mods0, Mods),
    maplist('$use_list_of_modules', Mods),
    '$repl'.
'$run'([], Mods0, Goals0) :-
    reverse(Mods0, Mods),
    reverse(Goals0, Goals),
    write('run with goals: todo\n').

'$use_list_of_modules'(Module) :-
    catch(use_module(Module), E, '$print_exception'(E)).

'$repl' :-
    catch('$read_and_match', E, '$print_exception'(E)),
    false. %% this is for GC, until we get actual GC.
'$repl' :-
    '$repl'.

'$read_and_match' :-
    '$read_query_term'(Term, VarList),
    '$instruction_match'(Term, VarList).

% make '$compile_batch', a system routine, callable.
'$$compile_batch' :- '$compile_batch'.

'$instruction_match'(Term, VarList) :-
    (  var(Term) ->
       throw(error(instantiation_error, repl/0))
    ;
       Term = [Item] -> !,
       (  atom(Item) ->
	      (  Item == user ->
	         catch('$$compile_batch', E, '$print_exception_with_check'(E))
	      ;  consult(Item)
	      )
       ;
	   catch(throw(error(type_error(atom, Item), repl/0)),
		     E,
		     '$print_exception_with_check'(E))
       )
    ;
       '$submit_query_and_print_results'(Term, VarList)
    ).

'$submit_query_and_print_results'(Term0, VarList) :-
    (  expand_goals(Term0, Term) -> true
    ;  Term0 = Term
    ),
    (  '$get_b_value'(B), write('   '), call(Term), '$write_eqs_and_read_input'(B, VarList),
       !
    %  clear attribute goal lists, which may be populated by
    %  copy_term/3 prior to failure.
    ;  '$clear_attribute_goals', write('false.'), nl
    ).

'$needs_bracketing'(Value, Op) :-
    catch((functor(Value, F, _),
	       current_op(EqPrec, EqSpec, Op),
	       current_op(FPrec, _, F)),
	      _,
	      false),
    (  EqPrec < FPrec -> true
    ;  '$quoted_token'(F) -> true
    ;  EqPrec == FPrec,
       memberchk(EqSpec, [fx,xfx,yfx])
    ).

'$fabricate_var_name'(VarName, N) :-
    char_code('A', AC),
    LN is N mod 26 + AC,
    char_code(LC, LN),
    NN is N // 26,
    (  NN =:= 0 ->
       atom_chars(VarName, ['_', LC])
    ;  number_chars(NN, NNChars),
       atom_chars(VarName, ['_', LC | NNChars])
    ).

'$var_list_contains_name'([VarName = _ | VarList], VarName0) :-
    (  VarName == VarName0 -> true
    ;  '$var_list_contains_name'(VarList, VarName0)
    ).

'$var_list_contains_variable'([_ = Var | VarList], Var0) :-
    (  Var == Var0 -> true
    ;  '$var_list_contains_variable'(VarList, Var0)
    ).

'$make_new_var_name'(V, VarName, N, N1, VarList) :-
    '$fabricate_var_name'(VarName0, N),
    (  '$var_list_contains_name'(VarList, VarName0) ->
       N0 is N + 1,
       '$make_new_var_name'(V, VarName, N0, N1, VarList)
    ;  VarName = VarName0,
       N1 is N + 1
    ).

'$extend_var_list'(Value, VarList, NewVarList) :-
    term_variables(Value, Vars),
    '$extend_var_list_'(Vars, 0, VarList, NewVarList).

'$extend_var_list_'([], N, VarList, VarList).
'$extend_var_list_'([V|Vs], N, VarList, NewVarList) :-
    (  '$var_list_contains_variable'(VarList, V) ->
       '$extend_var_list_'(Vs, N, VarList, NewVarList)
    ;  '$make_new_var_name'(V, VarName, N, N1, VarList),
       NewVarList = [VarName = V | NewVarList0],
       '$extend_var_list_'(Vs, N1, VarList, NewVarList0)
    ).

'$write_goal'(G, VarList, MaxDepth) :-
    (  G = (Var = Value) ->
       write(Var),
       write(' = '),
       (  '$needs_bracketing'(Value, (=)) ->
	  write('('),
	  write_term(Value, [quoted(true), variable_names(VarList), max_depth(MaxDepth)]),
	  write(')')
       ;  write_term(Value, [quoted(true), variable_names(VarList), max_depth(MaxDepth)])
       )
    ;  G == [] ->
       write('true')
    ;  write_term(G, [quoted(true), variable_names(VarList), max_depth(MaxDepth)])
    ).

'$write_last_goal'(G, VarList, MaxDepth) :-
    (  G = (Var = Value) ->
       write(Var),
       write(' = '),
       (  '$needs_bracketing'(Value, (=)) ->
	  write('('),
	  write_term(Value, [quoted(true), variable_names(VarList), max_depth(MaxDepth)]),
	  write(')')
       ;  write_term(Value, [quoted(true), variable_names(VarList), max_depth(MaxDepth)]),
	  (  '$trailing_period_is_ambiguous'(Value) ->
	     write(' ')
	  ;  true
	  )
       )
    ;  G == [] ->
       write('true')
    ;  write_term(G, [quoted(true), variable_names(VarList), max_depth(MaxDepth)])
    ).

'$write_eq'((G1, G2), VarList, MaxDepth) :-
    !,
    '$write_goal'(G1, VarList, MaxDepth),
    write(', '),
    '$write_eq'(G2, VarList, MaxDepth).
'$write_eq'(G, VarList, MaxDepth) :-
    '$write_last_goal'(G, VarList, MaxDepth).

'$graphic_token_char'(C) :-
    memberchk(C, ['#', '$', '&', '*', '+', '-', '.', ('/'), ':',
                  '<', '=', '>', '?', '@', '^', '~', ('\\')]).

'$list_last_item'([C], C) :- !.
'$list_last_item'([_|Cs], D) :-
    '$list_last_item'(Cs, D).

'$trailing_period_is_ambiguous'(Value) :-
    atom(Value),
    atom_chars(Value, ValueChars),
    '$list_last_item'(ValueChars, Char),
    '$graphic_token_char'(Char).

'$write_eqs_and_read_input'(B, VarList) :-
    '$extend_var_list'(VarList, VarList, NewVarList),
    sort(NewVarList, SortedVarList),
    '$get_b_value'(B0),
    '$gather_goals'(SortedVarList, SortedVarList, Goals),
    (  B0 == B ->
       (  Goals == [] ->
	  write('true.'), nl
       ;  thread_goals(Goals, ThreadedGoals, (',')),
	  '$write_eq'(ThreadedGoals, NewVarList, 20),
	  write('.'),
	  nl
       )
    ;  thread_goals(Goals, ThreadedGoals, (',')),
       '$write_eq'(ThreadedGoals, NewVarList, 20),
       '$read_input'(ThreadedGoals, NewVarList)
    ).

'$read_input'(ThreadedGoals, NewVarList) :-
    '$raw_input_read_char'(C),
    (  C == w ->
       nl,
       write('   '),
       '$write_eq'(ThreadedGoals, NewVarList, 0),
       '$read_input'(ThreadedGoals, NewVarList)
    ;  C == p ->
       nl,
       write('   '),
       '$write_eq'(ThreadedGoals, NewVarList, 20),
       '$read_input'(ThreadedGoals, NewVarList)
    ;  C == (';') ->
       nl, write(';  '), false
    ;  C == h ->
       '$help_message',
       '$read_input'(ThreadedGoals, NewVarList)
    ;  C == '.',
       nl, write(';  ...'), nl
    ).

'$help_message' :-
    nl, nl,
    write('SPACE, "n" or ";": next solution, if any\n'),
    write('".": stop enumeration\n'),
    write('"h": display this help message\n'),
    write('"w": write terms without depth limit\n'),
    write('"p": print terms with depth limit\n\n').

'$gather_query_vars'([_ = Var | Vars], QueryVars) :-
    (  var(Var) ->
       QueryVars = [Var | QueryVars1],
       '$gather_query_vars'(Vars, QueryVars1)
    ;  '$gather_query_vars'(Vars, QueryVars)
    ).
'$gather_query_vars'([], []).

'$is_a_different_variable'([_ = Binding | Pairs], Value) :-
    (  Value == Binding, !
    ;  '$is_a_different_variable'(Pairs, Value)
    ).

'$gather_goals'([], VarList, Goals) :-
    '$gather_query_vars'(VarList, QueryVars),
    copy_term(QueryVars, QueryVars, Goals).
'$gather_goals'([Var = Value | Pairs], VarList, Goals) :-
    (  (  nonvar(Value)
       ;  '$is_a_different_variable'(Pairs, Value)
       ) ->
       Goals = [Var = Value | Goals0],
       '$gather_goals'(Pairs, VarList, Goals0)
    ;  '$gather_goals'(Pairs, VarList, Goals)
    ).

'$print_exception'(E) :-
    write_term('caught: ', [quoted(false), max_depth(20)]),
    writeq(E),
    nl.

'$print_exception_with_check'(E) :-
    (  E = error(_, _:_) -> true % if the error source contains a line
                                 % number, a GNU-style error message
                                 % is expected to be printed instead.
    ;  '$print_exception'(E)
    ).

'$module_export'(Source, PI) :-
    (  nonvar(PI) ->
       (  PI = Name / Arity ->
	      (  var(Name) -> throw(error(instantiation_error, Source))
	      ;  integer(Arity) ->
	         (  \+ atom(Name) -> throw(error(type_error(atom, Name), Source))
	         ;  Arity < 0 -> throw(error(domain_error(not_less_than_zero, Arity), Source))
	         ;  true
	         )
	      ;  throw(error(type_error(integer, Arity), Source))
	      )
       ;  PI = op(Prec, Spec, Name) ->
	      (  integer(Prec) ->
	         (  \+ atom(Name) ->
		        throw(error(type_error(atom, Name), Source))
	         ;  Prec < 0 ->
		        throw(error(domain_error(not_less_than_zero, Prec), Source))
	         ;  Prec > 1200 ->
		        throw(error(domain_error(operator_precision, Prec), Source))
	         ;  memberchk(Spec, [xfy, yfx, xfx, fx, fy, yf, xf])
	         ;  throw(error(domain_error(operator_specification, Spec), Source))
	         )
	      ;  throw(error(type_error(integer, Prec), Source))
	      )
       ;  throw(error(type_error(module_export, PI), Source))
       )
    ;  throw(error(instantiation_error, Source))
    ).

consult(Item) :-
    (  atom(Item) -> use_module(Item)
    ;  throw(error(type_error(atom, Item), consult/1))
    ).

use_module(Module) :-
    (  nonvar(Module) ->
       (  Module = library(Filename) -> '$use_module'(Filename)
       ;  atom(Module) -> '$use_module_from_file'(Module)
       ;  throw(error(invalid_module_specifier, use_module/1))
       )
    ;  throw(error(instantiation_error, use_module/1))
    ).

use_module(Module, QualifiedExports) :-
    (  nonvar(Module) ->
       (  list_si(QualifiedExports) ->
	  maplist('$module_export'(use_module/2), QualifiedExports) ->
	  (  Module = library(Filename) ->
	     '$use_qualified_module'(Filename, QualifiedExports)
	  ;  atom(Module) ->
	     '$use_qualified_module_from_file'(Module, QualifiedExports)
	  ;  throw(error(invalid_module_specifier, use_module/2))
	  )
       ;  throw(error(type_error(list, QualifiedExports), use_module/2))
       )
    ;  throw(error(instantiation_error, use_module/2))
    ).


% expand goals in initialization directives.
user:term_expansion(Term0, (:- initialization(ExpandedGoals))) :-
    nonvar(Term0),
    Term0 = (:- initialization(Goals)),
    expand_goals(Goals, ExpandedGoals),
    Goals \== ExpandedGoals.

'$module_expand_goal'(UnexpandedGoals, ExpandedGoals) :-
    (  '$module_of'(Module, UnexpandedGoals),
       '$module_exists'(Module),
       Module:goal_expansion(UnexpandedGoals, ExpandedGoals),
       UnexpandedGoals \== ExpandedGoals ->
       true
    ;  user:goal_expansion(UnexpandedGoals, ExpandedGoals)
    ).

expand_goals(UnexpandedGoals, ExpandedGoals) :-
    nonvar(UnexpandedGoals),
    var(ExpandedGoals),
    (  '$module_expand_goal'(UnexpandedGoals, Goals) ->
       true
    ;  Goals = UnexpandedGoals
    ),
    (  Goals = (Goal0, Goals0) ->
       (  expand_goals(Goal0, Goal1) ->
	      expand_goals(Goals0, Goals1),
	      thread_goals(Goal1, ExpandedGoals, Goals1, (','))
       ;  expand_goals(Goals0, Goals1),
	      ExpandedGoals = (Goal0, Goals1)
       )
    ;  Goals = (Goals0 -> Goals1) ->
       expand_goals(Goals0, ExpandedGoals0),
       expand_goals(Goals1, ExpandedGoals1),
       ExpandedGoals = (ExpandedGoals0 -> ExpandedGoals1)
    ;  Goals = (Goals0 ; Goals1) ->
       expand_goals(Goals0, ExpandedGoals0),
       expand_goals(Goals1, ExpandedGoals1),
       ExpandedGoals = (ExpandedGoals0 ; ExpandedGoals1)
    ;  Goals = (\+ Goals0) ->
       expand_goals(Goals0, Goals1),
       ExpandedGoals = (\+ Goals1)
    ;  thread_goals(Goals, ExpandedGoals, (','))
    ;  Goals = ExpandedGoals
    ).

thread_goals(Goals0, Goals1, Hole, Functor) :-
    nonvar(Goals0),
    (  Goals0 = [G | Gs] ->
       (  Gs == [] ->
	      Goals1 =.. [Functor, G, Hole]
       ;  Goals1 =.. [Functor, G, Goals2],
	      thread_goals(Gs, Goals2, Hole, Functor)
       )
    ;  Goals1 =.. [Functor, Goals0, Hole]
    ).

thread_goals(Goals0, Goals1, Functor) :-
    nonvar(Goals0),
    (  Goals0 = [G | Gs] ->
       (  Gs = [] ->
	      Goals1 = G
       ;  Goals1 =.. [Functor, G, Goals2],
	      thread_goals(Gs, Goals2, Functor)
       )
    ;  Goals1 = Goals0
    ).
