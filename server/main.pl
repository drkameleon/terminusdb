:- module(server, [terminus_server/1]).

/** <module> HTTP server module
 *
 * This module implements the database server. It is primarily composed
 * of a number of RESTful APIs which exchange information in JSON format
 * over HTTP. This is intended as a mechanism for interprocess
 * communication via *API* and not as a fully fledged high performance
 * server.
 *
 **/

:- use_module(core(triple)).
:- use_module(core(util/utils)).

% configuration predicates
:- use_module(config(terminus_config),[]).

% Sockets
:- use_module(library(socket)).
:- use_module(library(ssl)).

% http server
:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_ssl_plugin)).
:- use_module(library(http/html_write)).


load_jwt_conditionally :-
    config:jwt_public_key_path(JWTPubKeyPath),
    (   JWTPubKeyPath = ''
    ->  true
    ;   use_module(library(jwt_io)),
        config:jwt_public_key_id(Public_Key_Id),
        set_setting(jwt_io:keys, [_{kid: Public_Key_Id,
                                    type: 'RSA',
                                    algorithm: 'RS256',
                                    public_key: JWTPubKeyPath}])).

:- load_jwt_conditionally.

terminus_server(_Argv) :-
    config:server(Server),
    config:server_port(Port),
    config:worker_amount(Workers),
    config:ssl_cert(CertFile),
    config:ssl_cert_key(CertKeyFile),
    (   config:https_enabled
    ->  HTTPOptions = [ssl([certificate_file(CertFile), key_file(CertKeyFile)]),
                        port(Port), workers(Workers)]
    ;   HTTPOptions = [port(Port), workers(Workers)]
    ),
    catch(http_server(http_dispatch, HTTPOptions),
          E,
          (
              writeq(E),
              format(user_error, "Error: Port ~d is already in use.", [Port]),
              halt(98) % EADDRINUSE
          )),
    setup_call_cleanup(
        http_handler(root(.), busy_loading,
                     [ priority(1000),
                       hide_children(true),
                       id(busy_loading),
                       time_limit(infinite),
                       prefix
                     ]),
        (   triple_store(_Store), % ensure triple store has been set up by retrieving it once
            welcome_banner(Server)
        ),
        http_delete_handler(id(busy_loading))).


% See https://github.com/terminusdb/terminusdb-server/issues/91
%  TODO replace this with a proper page
%
busy_loading(_) :-
    reply_html_page(
        title('Still Loading'),
        \loading_page).

loading_page -->
    html([
        h1('Still loading'),
        p('TerminusDB is still synchronizing backing store')
    ]).

welcome_banner(Server) :- 
    format(user_error,'~N% Welcome to TerminusDB\'s terminusdb-server!',[]),
    format(user_error,'~N% Welcome to TerminusDB\'s terminusdb-server!',[]),
         nl,
         '% You can view your server in a browser at \'~s\''-[Server],
         nl,
         nl
         ].
