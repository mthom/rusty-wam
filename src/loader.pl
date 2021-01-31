
:- module(loader, [consult/1,
                   expand_goal/3,
                   expand_term/2,
                   file_load/2,
                   load/1,
                   predicate_property/2,
                   prolog_load_context/2,
                   strip_module/3,
                   use_module/1,
                   use_module/2
                  ]).


:- use_module(library(error)).
:- use_module(library(lists)).
:- use_module(library(pairs)).


create_file_load_context(Stream, Path, Evacuable) :-
    '$push_load_context'(Stream, Path),
    '$push_load_state_payload'(Evacuable).

create_load_context(Stream, Evacuable) :-
    '$push_load_context'(Stream, ''),
    '$push_load_state_payload'(Evacuable).

unload_evacuable(Evacuable) :-
    '$pop_load_state_payload'(Evacuable),
    '$pop_load_context'.


file_load(Stream, Path) :-
    file_load(Stream, Path, _).

file_load(Stream, Path, Evacuable) :-
    create_file_load_context(Stream, Path, Evacuable),
    catch(loader:load_loop(Stream, Evacuable),
          E,
          (loader:unload_evacuable(Evacuable), throw(E))),
    '$pop_load_context'.


load(Stream) :-
    create_load_context(Stream, Evacuable),
    catch(loader:load_loop(Stream, Evacuable),
          E,
          (loader:unload_evacuable(Evacuable), throw(E))),
    '$pop_load_context'.

load_loop(Stream, Evacuable) :-
    read_term(Stream, Term, [variable_names(VNs), singletons(Singletons)]),
    (  Term == end_of_file ->
       close(Stream),
       '$conclude_load'(Evacuable)
    ;  var(Term) ->
       instantiation_error(load/1)
    ;  expand_terms_and_goals(Term, Terms),
       !,
       (  var(Terms) ->
          instantiation_error(load/1)
       ;  Terms = [_|_] ->
          compile_dispatch_or_clause_on_list(Terms, Evacuable, VNs)
       ;  compile_dispatch_or_clause(Terms, Evacuable, VNs)
       ),
       load_loop(Stream, Evacuable)
    ).


inner_meta_specs((:), HeadArg, InnerHeadArgs, InnerMetaSpecs) :-
    !,
    predicate_property(HeadArg, meta_predicate(InnerMetaSpecs)),
    HeadArg =.. [_ | InnerHeadArgs].

inner_meta_specs(N, HeadArg, InnerHeadArgs, InnerMetaSpecs) :-
    integer(N),
    N >= 0,
    HeadArg =.. [Functor | InnerHeadArgs],
    length(InnerHeadArgs1, N),
    append(InnerHeadArgs, InnerHeadArgs1, InnerHeadArgs0),
    CompleteHeadArg =.. [Functor | InnerHeadArgs0],
    predicate_property(CompleteHeadArg, meta_predicate(InnerMetaSpecs)).


module_expanded_head_variables_([], _, HeadVars, HeadVars).
module_expanded_head_variables_([HeadArg | HeadArgs], [MetaSpec | MetaSpecs], HeadVars, HeadVars0) :-
    (  (  MetaSpec == (:)
       ;  integer(MetaSpec),
          MetaSpec >= 0
       )  ->
       (  var(HeadArg) ->
          HeadVars = [HeadArg-HeadArg | HeadVars1],
          module_expanded_head_variables_(HeadArgs, MetaSpecs, HeadVars1, HeadVars0)
       ;  inner_meta_specs(MetaSpec, HeadArg, InnerHeadArgs, InnerMetaSpecs) ->
          module_expanded_head_variables_(InnerHeadArgs, InnerMetaSpecs, HeadVars, HeadVars1),
          module_expanded_head_variables_(HeadArgs, MetaSpecs, HeadVars1, HeadVars0)
       ;  module_expanded_head_variables_(HeadArgs, MetaSpecs, HeadVars, HeadVars0)
       )
    ;  module_expanded_head_variables_(HeadArgs, MetaSpecs, HeadVars, HeadVars0)
    ).

module_expanded_head_variables(Head, MetaSpecs, HeadVars) :-
    (  var(Head) ->
       instantiation_error(load/1)
    ;  predicate_property(Head, meta_predicate(MetaSpecs)),
       Head =.. [_ | HeadArgs] ->
       module_expanded_head_variables_(HeadArgs, MetaSpecs, HeadVars, [])
    ;  HeadVars = []
    ).


expand_terms_and_goals(Term, Terms) :-
    expand_term(Term, Terms0),
    (  var(Terms0) ->
       instantiation_error(load/1)
    ;  Terms0 = (Head1 :- Body0) ->
       (  var(Head1) ->
          instantiation_error(load/1)
       ;  prolog_load_context(module, Target),
          module_expanded_head_variables(Head1, MetaSpecs, HeadVars),
          expand_goal(Body0, Target, Body1, HeadVars)
       ),
       Terms = (Head1 :- Body1)
    ;  Terms = Terms0
    ).


expand_term(UnexpandedTerm, ExpandedTerm) :-
    user:term_expansion(UnexpandedTerm, ExpandedTerm).


compile_dispatch_or_clause_on_list([], Evacuable, VNs).
compile_dispatch_or_clause_on_list([Term | Terms], Evacuable, VNs) :-
    compile_dispatch_or_clause(Term, Evacuable, VNs),
    compile_dispatch_or_clause_on_list(Terms, Evacuable, VNs).


compile_dispatch_or_clause(Term, Evacuable, VNs) :-
    (  var(Term) ->
       instantiation_error(load/1)
    ;  compile_dispatch(Term, Evacuable, VNs) ->
       true
    ;
       compile_clause(Term, Evacuable, VNs)
    ).


compile_dispatch((:- Declaration), Evacuable, _VNs) :-
    (  var(Declaration) ->
       instantiation_error(load/1)
    ;
       compile_declaration(Declaration, Evacuable)
    ).
compile_dispatch(term_expansion(Term, Terms), Evacuable, VNs) :-
    '$add_term_expansion_clause'('$term_expansion'(Term, Terms), Evacuable, VNs).
compile_dispatch((term_expansion(Term, Terms) :- Body), Evacuable, VNs) :-
    '$add_term_expansion_clause'(('$term_expansion'(Term, Terms) :- Body), Evacuable, VNs).
compile_dispatch(user:term_expansion(Term, Terms), Evacuable, VNs) :-
    '$add_term_expansion_clause'('$term_expansion'(Term, Terms), Evacuable, VNs).
compile_dispatch((user:term_expansion(Term, Terms) :- Body), Evacuable, VNs) :-
    '$add_term_expansion_clause'(('$term_expansion'(Term, Terms) :- Body), Evacuable, VNs).
compile_dispatch(goal_expansion(Term, Terms), Evacuable, VNs) :-
    prolog_load_context(module, Target),
    '$add_goal_expansion_clause'(Target, goal_expansion(Term, Terms), Evacuable, VNs).
compile_dispatch((goal_expansion(Term, Terms) :- Body), Evacuable, VNs) :-
    prolog_load_context(module, Target),
    '$add_goal_expansion_clause'(Target, (goal_expansion(Term, Terms) :- Body), Evacuable, VNs).
compile_dispatch(Target:goal_expansion(Term, Terms), Evacuable, VNs) :-
    '$add_goal_expansion_clause'(Target, goal_expansion(Term, Terms), Evacuable, VNs).
compile_dispatch((Target:goal_expansion(Term, Terms) :- Body), Evacuable, VNs) :-
    '$add_goal_expansion_clause'(Target, (goal_expansion(Term, Terms) :- Body), Evacuable, VNs).


compile_declaration(use_module(Module), Evacuable) :-
    use_module(Module, [], Evacuable).
compile_declaration(use_module(Module, Exports), Evacuable) :-
    (  Exports == [] ->
       '$remove_module_exports'(Module, Evacuable) % TODO: implement this.
    ;
       use_module(Module, Exports, Evacuable)
    ).
compile_declaration(module(Module, Exports), Evacuable) :-
    ( atom(Module) ->
      '$declare_module'(Module, Exports, Evacuable)
    ;
      type_error(atom, Module, load/1)
    ).
compile_declaration(dynamic(Name/Arity), Evacuable) :-
    must_be(atom, Name),
    must_be(integer, Arity),
    '$add_dynamic_predicate'(Name, Arity, Evacuable).
compile_declaration(initialization(Goal), Evacuable) :-
    prolog_load_context(module, Module),
    '$compile_pending_predicates'(Evacuable),
    expand_goal(call(Goal), Module, call(ExpandedGoal)),
    call(ExpandedGoal).


compile_clause(Clause, Evacuable, VNs) :-
    '$clause_to_evacuable'(Clause, Evacuable, VNs).


prolog_load_context(source, Source) :-
    %% The absolute path name of the file being compiled. During
    %% loading of a PO file, the corresponding source file name is
    %% returned.
    '$prolog_lc_source'(Source).
prolog_load_context(file, File) :-
    %% Outside included files (see Include Declarations) this is the
    %% same as the source key. In included files this is the absolute
    %% path name of the file being included.
    '$prolog_lc_file'(File).
prolog_load_context(directory, Dir) :-
    %% The absolute path name of the directory of the file being
    %% compiled/loaded. In included files this is the directory of the
    %% file being included.
    '$prolog_lc_dir'(Dir).
prolog_load_context(module, Module) :-
    %% The source module (see ref-mod-mne). This is useful for example
    %% if you are defining clauses for user:term_expansion/6 and need
    %% to access the source module at compile time.
    '$prolog_lc_module'(Module).
prolog_load_context(stream, Stream) :-
    %% The stream being compiled or loaded from.
    '$prolog_lc_stream'(Stream).
prolog_load_context(term_position, TermPosition) :-
    %% TermPosition represents the stream position of the last term read.
    '$prolog_lc_stream'(Stream),
    stream_property(Stream, position(TermPosition)).


consult(Item) :-
    (  atom(Item) -> use_module(Item)
    ;  type_error(atom, Item, consult/1)
    ).


use_module(Module) :-
    '$push_load_state_payload'(Evacuable),
    use_module(Module, [], Evacuable).

use_module(Module, Exports) :-
    '$push_load_state_payload'(Evacuable),
    (  Exports == [] ->
       '$remove_module_exports'(Module, Evacuable)
    ;
       use_module(Module, Exports, Evacuable)
    ).


%% If use_module is invoked in an existing load context, use its
%% directory. Otherwise, use the relative path of Path.
load_context_path(Module, Path) :-
    (  prolog_load_context(directory, CurrentDir) ->
       atom_concat(CurrentDir, Path, Module)
    ;
       Module = Path
    ).

use_module(Module, Exports, Evacuable) :-
    (  var(Module) ->
       instantiation_error(load/1)
    ;  Module = library(Library) ->
       (  atom(Library) ->
          (  '$load_compiled_library'(Library, Evacuable) -> %% TODO: What about Exports?
             true
          ;
             '$load_library_as_stream'(Library, Stream, Path),
             file_load(Stream, Path, Subevacuable),
             '$use_module'(Evacuable, Subevacuable, Exports)
          )
       ;  var(Library) ->
          instantiation_error(load/1)
       ;
          type_error(atom, Library, load/1)
       )
    ;  atom(Module) ->
       load_context_path(Module, Path),
       open(Path, read, Stream),
       file_load(Stream, Path, Subevacuable),
       '$use_module'(Evacuable, Subevacuable, Exports)
    ;
       type_error(atom, Library, load/1)
    ).



check_predicate_property(meta_predicate, Name, Arity, MetaPredicateTerm) :-
    must_be(atom, Name),
    must_be(integer, Arity),
    '$cpp_meta_predicate_property'(Name, Arity, MetaPredicateTerm).


predicate_property(Callable, Property) :-
    (  var(Callable) ->
       instantiation_error(load/1)
    ;  functor(Callable, Name, Arity),
       (  var(Property) ->
          true
       ;  functor(Property, PropertyType, _)
       ),
       check_predicate_property(PropertyType, Name, Arity, Property)
    ).


strip_module_(M0, G0, M1, G1) :-
    (  nonvar(G0),
       G0 = (MG1:G2) ->
       strip_module_(MG1, G2, M1, G1)
    ;  M0 = M1,
       G0 = G1
    ).

strip_module(Goal, M, G) :-
    strip_module_(_, Goal, M, G).



expand_subgoal(UnexpandedGoals, MS, Module, ExpandedGoals, HeadVars) :-
    (  var(UnexpandedGoals) ->
       UnexpandedGoals = ExpandedGoals
    ;  user:goal_expansion(UnexpandedGoals, Module, UnexpandedGoals1),
       (  Module \== user ->
          user:goal_expansion(UnexpandedGoals1, user, Goals)
       ;  Goals = UnexpandedGoals1
       ),
       (  inner_meta_specs(MS, Goals, _, MetaSpecs) ->
          expand_module_names(Goals, MetaSpecs, Module, ExpandedGoals, HeadVars)
       ;  Goals = ExpandedGoals
       )
    ;  UnexpandedGoals = ExpandedGoals
    ).


expand_module_name(ESG0, M, ESG) :-
    (  var(ESG0) ->
       ESG = M:ESG0
    ;  ESG0 = _:ESG1 ->
       ESG = ESG0
    ;  ESG = M:ESG0
    ).


expand_meta_predicate_subgoals([SG | SGs], [MS | MSs], M, [ESG | ESGs], HeadVars) :-
    (  (  MS == (:)
       ;  integer(MS),
          MS >= 0
       )  ->
       (  var(SG),
          pairs:same_key(SG, HeadVars, [_|_], _) ->
          expand_subgoal(SG, MS, M, ESG, HeadVars)
       ;  expand_subgoal(SG, MS, M, ESG0, HeadVars),
          expand_module_name(ESG0, M, ESG)
       ),
       expand_meta_predicate_subgoals(SGs, MSs, M, ESGs, HeadVars)
    ;  ESG = SG,
       expand_meta_predicate_subgoals(SGs, MSs, M, ESGs, HeadVars)
    ).

expand_meta_predicate_subgoals([], _, _, [], _).


expand_module_names(Goals, MetaSpecs, Module, ExpandedGoals, HeadVars) :-
    Goals =.. [GoalFunctor | SubGoals],
    (  GoalFunctor == (:) ->
       false
    ;  expand_meta_predicate_subgoals(SubGoals, MetaSpecs, Module, ExpandedGoalList, HeadVars),
       ExpandedGoals =.. [GoalFunctor | ExpandedGoalList]
    ).


expand_goal(UnexpandedGoals, Module, ExpandedGoals) :-
    expand_goal(UnexpandedGoals, Module, ExpandedGoals, []),
    !.

expand_goal(UnexpandedGoals, Module, ExpandedGoals, HeadVars) :-
    (  var(UnexpandedGoals) ->
       UnexpandedGoals = ExpandedGoals
    ;  user:goal_expansion(UnexpandedGoals, Module, UnexpandedGoals1),
       (  Module \== user ->
          user:goal_expansion(UnexpandedGoals1, user, Goals)
       ;  Goals = UnexpandedGoals1
       ),
       (  Goals = (Goal0, Goals0) ->
          (  expand_goal(Goal0, Module, Goal1, HeadVars) ->
             expand_goal(Goals0, Module, Goals1, HeadVars),
             thread_goals(Goal1, ExpandedGoals, Goals1, (','))
          ;  expand_goal(Goals0, Module, Goals1, HeadVars),
             ExpandedGoals = (Goal0, Goals1)
          )
       ;  Goals = (Goals0 -> Goals1) ->
          expand_goal(Goals0, Module, ExpandedGoals0, HeadVars),
          expand_goal(Goals1, Module, ExpandedGoals1, HeadVars),
          ExpandedGoals = (ExpandedGoals0 -> ExpandedGoals1)
       ;  Goals = (Goals0 ; Goals1) ->
          expand_goal(Goals0, Module, ExpandedGoals0, HeadVars),
          expand_goal(Goals1, Module, ExpandedGoals1, HeadVars),
          ExpandedGoals = (ExpandedGoals0 ; ExpandedGoals1)
       ;  Goals = (\+ Goals0) ->
          expand_goal(Goals0, Module, Goals1, HeadVars),
          ExpandedGoals = (\+ Goals1)
       ;  predicate_property(Goals, meta_predicate(MetaSpecs)) ->
          expand_module_names(Goals, MetaSpecs, Module, ExpandedGoals, HeadVars)
       ;  thread_goals(Goals, ExpandedGoals, (','))
       ;  Goals = ExpandedGoals
       )
    ).

thread_goals(Goals0, Goals1, Functor) :-
    (  var(Goals0) ->
       Goals0 = Goals1
    ;  (  Goals0 = [G | Gs] ->
          (  Gs = [] ->
             Goals1 = G
          ;  Goals1 =.. [Functor, G, Goals2],
             thread_goals(Gs, Goals2, Functor)
          )
       ;  Goals1 = Goals0
       )
    ).

thread_goals(Goals0, Goals1, Hole, Functor) :-
    (  var(Goals0) ->
       Goals1 =.. [Functor, Goals0, Hole]
    ;  (  Goals0 = [G | Gs] ->
          (  Gs == [] ->
             Goals1 =.. [Functor, G, Hole]
          ;  Goals1 =.. [Functor, G, Goals2],
             thread_goals(Gs, Goals2, Hole, Functor)
          )
       ;  Goals1 =.. [Functor, Goals0, Hole]
       )
    ).