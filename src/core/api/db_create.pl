:- module(db_create, [
              create_db_unfinalized/9,
              create_db/9,
              create_ref_layer/2,
              finalize_db/1
          ]).

/** <module> Implementation of database graph management
 *
 * This module helps other modules with the representation of databases and
 * their associated graphs by bundling them as objects with some convenience
 * operators and accessors.
 *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

:- reexport(core(util/syntax)).
:- use_module(core(util)).
:- use_module(core(triple)).
:- use_module(core(query)).
:- use_module(core(transaction)).
:- use_module(core(account)).
:- use_module(core(api/db_graph)).

:- use_module(library(terminus_store)).
:- use_module(core(util/test_utils)).

:- multifile prolog:message//1.
prolog:message(error(database_exists(Name), _)) -->
                [ 'The database ~w already exists'-[Name]].

local_repo_uri(Name, Uri) :-
    atomic_list_concat(['terminusdb:///repository/', Name, '/data/Local'], Uri).

/**
 * create_repo_graph(+Organization,+Name)
 */
create_repo_graph(Organization,Database) :-
    triple_store(Store),
    organization_database_name(Organization,Database,Name),
    safe_create_named_graph(Store,Name,_Graph),
    Descriptor = database_descriptor{ organization_name : Organization,
                                      database_name: Database },
    create_context(Descriptor, Context),
    with_transaction(Context,
                     insert_local_repository(Context, "local", _),
                     _).

create_ref_layer(Descriptor,Prefixes) :-
    create_context(Descriptor, Context),
    with_transaction(
        Context,
        (   insert_branch_object(Context, "main", _),
            update_prefixes(Context, Prefixes)
        ),
        _).

finalize_db(DB_Uri) :-
    create_context(system_descriptor{}, Context),
    with_transaction(
        Context,
        (   ask(Context, (
                    t(DB_Uri, rdf:type, system:'Database'),
                    not(t(DB_Uri, system:database_state, _))
                ))
        ->  ask(Context,
                insert(DB_Uri, system:database_state, system:finalized))
        ;   throw(error(database_in_inconsistent_state))),
        _).

make_db_public(System_Context,DB_Uri) :-
    ask(System_Context,
        (   random_idgen(doc:'Capability', ["anonymous"^^xsd:string], Capability_Uri),
            insert(doc:anonymous_role, system:capability, Capability_Uri),
            insert(Capability_Uri, rdf:type, system:'Capability'),
            insert(Capability_Uri, system:capability_scope, DB_Uri),
            insert(Capability_Uri, system:action, system:class_frame),
            insert(Capability_Uri, system:action, system:clone),
            insert(Capability_Uri, system:action, system:fetch),
            insert(Capability_Uri, system:action, system:branch),
            insert(Capability_Uri, system:action, system:instance_read_access),
            insert(Capability_Uri, system:action, system:schema_read_access),
            insert(Capability_Uri, system:action, system:inference_read_access),
            insert(Capability_Uri, system:action, system:commit_read_access),
            insert(Capability_Uri, system:action, system:meta_read_access))).

create_db_unfinalized(System_DB, Auth, Organization_Name,Database_Name, Label, Comment, Public, Prefixes, Db_Uri) :-
    % Run the initial checks and insertion of db object in system graph inside of a transaction.
    % If anything fails, everything is retried, including the auth checks.
    create_context(System_DB, System_Context),
    with_transaction(
        System_Context,
        (
            % don't create if already exists
            do_or_die(organization_name_uri(System_Context, Organization_Name, Organization_Uri),
                      error(unknown_organization(Organization_Name),_)),
            assert_auth_action_scope(System_Context, Auth, system:create_database, Organization_Uri),

            do_or_die(
                not(database_exists(Organization_Name, Database_Name)),
                error(database_already_exists(Organization_Name, Database_Name),_)),

            text_to_string(Organization_Name, Organization_Name_String),
            text_to_string(Database_Name, Database_Name_String),

            % insert new db object into the terminus db
            insert_db_object(System_Context, Organization_Name_String, Database_Name_String, Label, Comment, Db_Uri),

            (   Public = true
            ->  make_db_public(System_Context, Db_Uri)
            ;   true)
        ),
        _),

    % create repo graph - it has name as label
    % This is outside of the transaction because it has side-effects that cannot be rolled back.
    create_repo_graph(Organization_Name_String, Database_Name_String),

    % create ref layer with master branch
    Repository_Descriptor = repository_descriptor{
                                database_descriptor:
                                database_descriptor{
                                    organization_name: Organization_Name_String,
                                    database_name: Database_Name_String
                                },
                                repository_name: "local"
                            },
    create_ref_layer(Repository_Descriptor,Prefixes).

default_schema_path(Organization_Name, Database_Name, Graph_Path) :-
    atomic_list_concat([Organization_Name, '/', Database_Name, '/',
                        "local/branch/main/schema/main"], Graph_Path).

create_db(System_DB, Auth, Organization_Name, Database_Name, Label, Comment, Public, Schema, Prefixes) :-
    create_db_unfinalized(System_DB, Auth, Organization_Name, Database_Name, Label, Comment, Public, Prefixes, Db_Uri),
    % Create schema graph
    (   Schema = true
    ->  default_schema_path(Organization_Name, Database_Name, Graph_Path),
        Commit_Info = _{ author : "TerminusDB",
                         message : "internal system operation" },
        create_graph(system_descriptor{}, Auth, Graph_Path, Commit_Info, _)
    ;   true),
    % update system with finalized
    % This reopens system graph internally, as it was advanced
    finalize_db(Db_Uri).

:- begin_tests(database_creation).
:- use_module(core(util/test_utils)).
:- use_module(core(query)).

test(create_db_and_check_master_branch, [
         setup(setup_temp_store(State)),
         cleanup(teardown_temp_store(State)),

         true((once(ask(Repo_Descriptor, t(_,ref:branch_name,"main"^^xsd:string))),
               \+ ask(Branch_Descriptor, t(_,_,_))))
         ])
:-
    Prefixes = _{ doc : 'http://somewhere/document', scm : 'http://somewhere/schema' },
    open_descriptor(system_descriptor{}, System),
    create_db(System, doc:admin, admin, testdb, 'testdb', 'a test db', false, false, Prefixes),
    Database_Descriptor = database_descriptor{
                              organization_name: "admin",
                              database_name: "testdb" },
    Repo_Descriptor = repository_descriptor{
                          database_descriptor: Database_Descriptor,
                          repository_name: "local" },
    Branch_Descriptor = branch_descriptor{
                            repository_descriptor: Repo_Descriptor,
                            branch_name: "main" }.

:- end_tests(database_creation).
