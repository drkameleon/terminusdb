:- module(api, [
              % db_delete.pl
              delete_db/1,
              % db_init.pl
              create_db/2,
              % init.pl
              initialize_config/4,
              initialize_registry/0,
              initialize_index/3,
              initialize_database/2,
              initialize_database_with_path/3,
              initialize_database_with_store/3
          ]).

:- use_module(api/init).
:- use_module(api/db_init).
:- use_module(api/db_delete).
