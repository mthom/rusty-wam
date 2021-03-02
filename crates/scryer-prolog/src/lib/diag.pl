:- module(diag, [wam_instructions/2]).

:- use_module(library(error)).


wam_instructions(Clause, Listing) :-
    (  nonvar(Clause) ->
       (  Clause = Name / Arity ->
          fetch_instructions(user, Name, Arity, Listing)
       ;  Clause = Module : (Name / Arity) ->
          fetch_instructions(Module, Name, Arity, Listing)
       )
    ;  throw(error(instantiation_error, wam_instructions/2))
    ).


fetch_instructions(Module, Name, Arity, Listing) :-
    must_be(atom, Module),
    must_be(atom, Name),
    must_be(integer, Arity),
    (  Arity >= 0 ->
       '$wam_instructions'(Module, Name, Arity, Listing)
    ;  throw(error(domain_error(not_less_than_zero, Arity), wam_instructions/2))
    ).
