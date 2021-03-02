:- module('$project_atts', [copy_term/3]).

driver(QueryVars, AttrVars) :-
    gather_attr_modules(AttrVars, Modules0),
    sort(Modules0, Modules),
    call_project_attributes(Modules, QueryVars, AttrVars),
    call_attribute_goals(Modules, '$project_atts':call_query_var_goals, QueryVars),
    call_attribute_goals(Modules, '$project_atts':call_attr_var_goals, AttrVars).

enqueue_goals(Goals0) :-
    nonvar(Goals0),
    Goals0 = [Goal | Goals],
    nonvar(Goal),
    !,
    '$enqueue_attribute_goal'(Goal),
    enqueue_goals(Goals).
enqueue_goals(_).

'$print_project_attributes_exception'(Module, E) :-
    (  E = error(evaluation_error((Module:project_attributes)/2), project_attributes/2) ->
       true
    ;  write_term('caught: ', [quoted(false)]),
       writeq(E),
       nl
    ).

call_project_attributes([], _, _).
call_project_attributes([Module|Modules], QueryVars, AttrVars) :-
    (   catch(Module:project_attributes(QueryVars, AttrVars),
	      E,
	      '$print_project_attributes_exception'(Module, E)
	     )
    ->  true
    ;   true
    ),
    call_project_attributes(Modules, QueryVars, AttrVars).

call_attribute_goals([], _, _).
call_attribute_goals([Module|Modules], GoalCaller, AttrVars) :-
    call(GoalCaller, AttrVars, Module, Goals),
    enqueue_goals(Goals),
    call_attribute_goals(Modules, GoalCaller, AttrVars).

'$print_attribute_goals_exception'(Module, E) :-
    (  E = error(evaluation_error((Module:attribute_goals)/3), attribute_goals/3)
    -> true
    ;  write_term('caught: ', [quoted(false)]),
       writeq(E),
       nl
    ).

call_query_var_goals([], _, []).
call_query_var_goals([AttrVar|AttrVars], Module, Goals) :-
    (  catch((  Module:attribute_goals(AttrVar, Goals, RGoals0),
	            atts:'$default_attr_list'(Module, AttrVar, RGoals0, RGoals)
	         ),
	         E,
	         (  '$project_atts':'$print_attribute_goals_exception'(Module, E),
		        atts:'$default_attr_list'(Module, AttrVar, Goals, RGoals)
	         ))
    -> true
    ;  atts:'$default_attr_list'(Module, AttrVar, Goals, RGoals)
    ),
    call_query_var_goals(AttrVars, Module, RGoals).

call_attr_var_goals([], _, []).
call_attr_var_goals([AttrVar|AttrVars], Module, Goals) :-
    (  catch(Module:attribute_goals(AttrVar, Goals, RGoals),
	         E,
	         '$project_atts':'$print_attribute_goals_exception'(Module, E)
	        )
    -> true
    ;  true
    ),
    call_attr_var_goals(AttrVars, Module, RGoals).


module_prefixed_goals([], _, Gs, Gs).
module_prefixed_goals([G|Gs], Module, [MG|MGs], TailGs) :-
    (  G = _:_ -> MG = G
    ;  MG = Module:G
    ),
    module_prefixed_goals(Gs, Module, MGs, TailGs).

call_attribute_goals_with_module_prefix([], _, _, []).
call_attribute_goals_with_module_prefix([Module | Modules], GoalCaller, AttrVars, Goals) :-
    call(GoalCaller, AttrVars, Module, Goals0),
    enqueue_goals(Goals0),
    module_prefixed_goals(Goals0, Module, Goals, Gs),
    call_attribute_goals_with_module_prefix(Modules, GoalCaller, AttrVars, Gs).


gather_attr_modules([], []).
gather_attr_modules([AttrVar|AttrVars], Modules) :-
    '$get_attr_list'(AttrVar, Attrs),
    copy_attribute_modules(Attrs, Modules, Modules0),
    gather_attr_modules(AttrVars, Modules0).

copy_attribute_modules(Attrs, Ls, Ls) :-
    var(Attrs), !.
copy_attribute_modules([Module:_|Attrs], [Module|Modules0], Modules1) :-
    copy_attribute_modules(Attrs, Modules0, Modules1).


copy_term(Source, Dest, Goals) :-
    '$term_attributed_variables'(Source, AttrVars),
    gather_attr_modules(AttrVars, Modules0),
    sort(Modules0, Modules),
    call_attribute_goals_with_module_prefix(Modules, '$project_atts':call_query_var_goals,
                                            AttrVars, Goals0),
    sort(Goals0, Goals1),
    !,
    '$copy_term_without_attr_vars'([Source | Goals1], [Dest | Goals]).
