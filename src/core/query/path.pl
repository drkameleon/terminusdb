:- module(path,[
              compile_pattern/4,
              calculate_path_solutions/6
          ]).

:- use_module(core(util)).
:- use_module(core(triple)).
:- use_module(core(validation)).

hop(type_filter{ types : Types}, X, P, Y, Transaction_Object) :-
    memberchk(instance,Types),
    inference:inferredEdge(X,P,Y,Transaction_Object).
hop(type_name_filter{ type : instance , names : _Names}, X, P, Y, Transaction_Object) :-
    inference:inferredEdge(X,P,Y,Transaction_Object).
hop(type_filter{ types : Types}, X, P, Y, Transaction_Object) :-
    memberchk(schema,Types),
    xrdf(Transaction_Object.schema_objects, X, P, Y).
hop(type_name_filter{ type : schema , names : _Names}, X, P, Y, Transaction_Object) :-
    xrdf(Transaction_Object.schema_objects, X, P, Y).
hop(type_filter{ types : Types}, X, P, Y, Transaction_Object) :-
    memberchk(inference,Types),
    xrdf(Transaction_Object.inference_objects, X, P, Y).
hop(type_name_filter{ type : inference , names : _Names}, X, P, Y, Transaction_Object) :-
    xrdf(Transaction_Object.inference_objects, X, P, Y).

calculate_path_solutions(Pattern,XE,YE,Path,Filter,Transaction_Object) :-
    run_pattern(Pattern,XE,YE,Path,Filter,Transaction_Object).

/**
 * in_open_set(+Elt,+Set) is semidet.
 *
 * memberchk for partially bound objects
 */
in_open_set(_Elt,Set) :-
    var(Set),
    !,
    fail.
in_open_set(Elt,[Elt|_]) :-
    !.
in_open_set(Elt,[_|Set]) :-
    in_open_set(Elt,Set).

make_edge(X,P,Y,
          _{ '@type' : "http://terminusdb.com/schema/woql#Edge",
             'http://terminusdb.com/schema/woql#subject' : X,
             'http://terminusdb.com/schema/woql#predicate' : P,
             'http://terminusdb.com/schema/woql#object' : Y}).

run_pattern(P,X,Y,Path,Filter,Transaction_Object) :-
    ground(Y),
    var(X),
    !,
    run_pattern_backward(P,X,Y,Rev,Rev-[],Filter,Transaction_Object),
    reverse(Rev,Path).
run_pattern(P,X,Y,Path,Filter,Transaction_Object) :-
    run_pattern_forward(P,X,Y,Path,Path-[],Filter,Transaction_Object).

run_pattern_forward(n(P),X,Y,Open_Set,_Path,_Filter,_Transaction_Object) :-
    make_edge(X,P,Y,Edge),
    in_open_set(Edge,Open_Set),
    !,
    fail.
run_pattern_forward(n(P),X,Y,_Open_Set,[Edge|Tail]-Tail,Filter,Transaction_Object) :-
    make_edge(X,P,Y,Edge),
    hop(Filter,Y,P,X,Transaction_Object).
run_pattern_forward(p(P),X,Y,Open_Set,_Path,_Filter,_Transaction_Object) :-
    make_edge(X,P,Y,Edge),
    in_open_set(Edge,Open_Set),
    !,
    fail.
run_pattern_forward(p(P),X,Y,_Open_Set,[Edge|Tail]-Tail,Filter,Transaction_Object) :-
    make_edge(X,P,Y,Edge),
    hop(Filter,X,P,Y,Transaction_Object).
run_pattern_forward((P,Q),X,Y,Open_Set,Path-Tail,Filter,Transaction_Object) :-
    run_pattern_forward(P,X,Z,Open_Set,Path-Path_M,Filter,Transaction_Object),
    run_pattern_forward(Q,Z,Y,Open_Set,Path_M-Tail,Filter,Transaction_Object).
run_pattern_forward((P;Q),X,Y,Open_Set,Path-Tail,Filter,Transaction_Object) :-
    (   run_pattern_forward(P,X,Y,Open_Set,Path-Tail,Filter,Transaction_Object)
    ;   run_pattern_forward(Q,X,Y,Open_Set,Path-Tail,Filter,Transaction_Object)).
run_pattern_forward(star(P),X,Y,Open_Set,Path-Tail,Filter,Transaction_Object) :-
    (   X = Y,
        Path = Tail
    ;   run_pattern_n_m_forward(P,1,-1,X,Y,Open_Set,Path-Tail,Filter,Transaction_Object)).
run_pattern_forward(plus(P),X,Y,Open_Set,Path-Tail,Filter,Transaction_Object) :-
    run_pattern_n_m_forward(P,1,-1,X,Y,Open_Set,Path-Tail,Filter,Transaction_Object).
run_pattern_forward(times(P,N,M),X,Y,Open_Set,Path-Tail,Filter,Transaction_Object) :-
    run_pattern_n_m_forward(P,N,M,X,Y,Open_Set,Path-Tail,Filter,Transaction_Object).

run_pattern_n_m_forward(P,1,_,X,Y,Open_Set,Path-Tail,Filter,Transaction_Object) :-
    run_pattern_forward(P,X,Y,Open_Set,Path-Tail,Filter,Transaction_Object).
run_pattern_n_m_forward(P,N,M,X,Y,Open_Set,Path-Tail,Filter,Transaction_Object) :-
    \+ M = 1, % M=1 is finished! M<1 is infinite.
    Np is max(1,N-1),
    Mp is M-1,
    run_pattern_forward(P,X,Z,Open_Set,Path-Path_IM,Filter,Transaction_Object),
    run_pattern_n_m_forward(P,Np,Mp,Z,Y,Open_Set,Path_IM-Tail,Filter,Transaction_Object).

run_pattern_backward(n(P),X,Y,Open_Set,_Path,_Filter,_Transaction_Object) :-
    make_edge(X,P,Y,Edge),
    in_open_set(Edge,Open_Set),
    !,
    fail.
run_pattern_backward(n(P),X,Y,_Open_Set,[Edge|Tail]-Tail,Filter,Transaction_Object) :-
    make_edge(X,P,Y,Edge),
    hop(Filter,Y,P,X,Transaction_Object).
run_pattern_backward(p(P),X,Y,Open_Set,_Path,_Filter,_Transaction_Object) :-
    make_edge(X,P,Y,Edge),
    in_open_set(Edge,Open_Set),
    !,
    fail.
run_pattern_backward(p(P),X,Y,_Open_Set,[Edge|Tail]-Tail,Filter,Transaction_Object) :-
    make_edge(X,P,Y,Edge),
    hop(Filter,X,P,Y,Transaction_Object).
run_pattern_backward((P,Q),X,Y,Open_Set,Path-Tail,Filter,Transaction_Object) :-
    run_pattern_backward(Q,ZE,Y,Open_Set,Path_M-Tail,Filter,Transaction_Object),
    run_pattern_backward(P,X,ZE,Open_Set,Path-Path_M,Filter,Transaction_Object).
run_pattern_backward((P;Q),X,Y,Open_Set,Path-Tail,Filter,Transaction_Object) :-
    (   run_pattern_backward(P,X,Y,Open_Set,Path-Tail,Filter,Transaction_Object)
    ;   run_pattern_backward(Q,X,Y,Open_Set,Path-Tail,Filter,Transaction_Object)).
run_pattern_backward(star(P),X,Y,Open_Set,Path-Tail,Filter,Transaction_Object) :-
    (   X = Y,
        Path = Tail
    ;   run_pattern_n_m_forward(P,1,-1,X,Y,Open_Set,Path-Tail,Filter,Transaction_Object)).
run_pattern_backward(plus(P),X,Y,Open_Set,Path-Tail,Filter,Transaction_Object) :-
    run_pattern_n_m_backward(P,1,-1,X,Y,Open_Set,Path-Tail,Filter,Transaction_Object).
run_pattern_backward(times(P,N,M),X,Y,Open_Set,Path-Tail,Filter,Transaction_Object) :-
    run_pattern_n_m_backward(P,N,M,X,Y,Open_Set,Path-Tail,Filter,Transaction_Object).

run_pattern_n_m_backward(P,1,_,X,Y,Open_Set,Path-Tail,Filter,Transaction_Object) :-
    run_pattern_backward(P,X,Y,Open_Set,Path-Tail,Filter,Transaction_Object).
run_pattern_n_m_backward(P,N,M,X,Y,Open_Set,Path-Tail,Filter,Transaction_Object) :-
    \+ M = 1, % M=1 is finished! M<1 is infinite.
    Np is max(1,N-1),
    Mp is M-1,
    run_pattern_backward(P,Z,Y,Open_Set,Path-Path_IM,Filter,Transaction_Object),
    run_pattern_n_m_backward(P,Np,Mp,X,Z,Open_Set,Path_IM-Tail,Filter,Transaction_Object).

/*
 * patterns have the following syntax:
 *
 * P,Q,R := p(P) | n(P) | P,Q | P;Q | plus(P) | times(P,N,M)
 *
 * foo>,<baz,bar>
 */
compile_pattern(n(Pred), Compiled, Prefixes, Transaction_Object) :-
    prefixed_to_uri(Pred,Prefixes,Pred_Expanded),
    sol_set({Transaction_Object,Pred_Expanded}/[n(Sub)]>>(
                subsumption_properties_of(Sub,Pred_Expanded,Transaction_Object)
            ), Predicates),
    xfy_list(';',Compiled,Predicates).
compile_pattern(p(Pred), Compiled, Prefixes, Transaction_Object) :-
    prefixed_to_uri(Pred,Prefixes,Pred_Expanded),
    sol_set({Transaction_Object,Pred_Expanded}/[p(Sub)]>>(
                subsumption_properties_of(Sub,Pred_Expanded,Transaction_Object)
            ), Predicates),
    xfy_list(';',Compiled,Predicates).
compile_pattern((X,Y), (XC,YC), Prefixes, Transaction_Object) :-
    compile_pattern(X,XC,Prefixes,Transaction_Object),
    compile_pattern(Y,YC,Prefixes,Transaction_Object).
compile_pattern((X;Y), (XC;YC), Prefixes, Transaction_Object) :-
    compile_pattern(X,XC,Prefixes,Transaction_Object),
    compile_pattern(Y,YC,Prefixes,Transaction_Object).
compile_pattern(star(X), star(XC), Prefixes, Transaction_Object) :-
    compile_pattern(X,XC,Prefixes,Transaction_Object).
compile_pattern(plus(X), plus(XC), Prefixes, Transaction_Object) :-
    compile_pattern(X,XC,Prefixes,Transaction_Object).
compile_pattern(times(X,N,M), times(XC,N,M), Prefixes, Transaction_Object) :-
    compile_pattern(X,XC,Prefixes,Transaction_Object).

right_edges(p(P),[P]).
right_edges(plus(P),Ps) :-
    right_edges(P,Ps).
right_edges(star(P),Ps) :-
    right_edges(P,Ps).
right_edges(times(P,_,_),Ps) :-
    right_edges(P,Ps).
right_edges((X,_Y),Ps) :-
    right_edges(X,Ps).
right_edges((X;Y),Rs) :-
    right_edges(X,Ps),
    right_edges(Y,Qs),
    append(Ps,Qs,Rs).

left_edges(p(P),[P]).
left_edges(star(P),Ps) :-
    left_edges(P,Ps).
left_edges(plus(P),Ps) :-
    left_edges(P,Ps).
left_edges(times(P,_,_),Ps) :-
    left_edges(P,Ps).
left_edges((_X,Y),Ps) :-
    left_edges(Y,Ps).
left_edges((X;Y),Rs) :-
    left_edges(X,Ps),
    left_edges(Y,Qs),
    append(Ps,Qs,Rs).
