%% This Source Code Form is subject to the terms of the Mozilla Public
%% License, v. 2.0. If a copy of the MPL was not distributed with this
%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%
%% Copyright (c) 2007-2025 Broadcom. All Rights Reserved. The term “Broadcom” refers to Broadcom Inc. and/or its subsidiaries. All rights reserved.
%%

-module(rabbit_auth_backend_ldap_util).

-export([fill/2, get_active_directory_args/1]).

%% Raw substitution without escaping. Safe only for non-DN sinks (ACL string
%% comparisons, eldap:equalityMatch/2 filter values). To build a DN, use
%% rabbit_ldap_rfc4514:fill_dn/2, which RFC 4514-escapes substituted values.
fill(Fmt, []) ->
    binary_to_list(iolist_to_binary(Fmt));

fill(Fmt, [{K, V} | T]) ->
    Var = [[$\\, $$, ${] ++ atom_to_list(K) ++ [$}]],
    fill(re:replace(Fmt, Var, [to_repl(V)], [global]), T).

to_repl(V) when is_atom(V)   -> to_repl(atom_to_list(V));
to_repl(V) when is_binary(V) -> to_repl(binary_to_list(V));
to_repl([])                  -> [];
to_repl([$\\ | T])           -> [$\\, $\\ | to_repl(T)];
to_repl([$&  | T])           -> [$\\, $&  | to_repl(T)];
to_repl([H   | T])           -> [H        | to_repl(T)];
to_repl(_)                   -> []. % fancy variables like peer IP are just ignored

%% If Username is in Domain\User format, provide additional fill template
%% arguments.
%%
%% Only binary Usernames are split: a 2-element split/1 result is only
%% meaningful for a genuine Domain\User binary, and matching on any
%% 2-element list here would also (mis)fire for an unrelated plain-string
%% Username of exactly two characters.
get_active_directory_args(Username) when is_binary(Username) ->
    split_active_directory_args(binary:split(Username, <<"\\">>, [trim_all]));
get_active_directory_args(_Username) ->
    [].

split_active_directory_args([ADDomain, ADUser]) ->
    [{ad_domain, ADDomain}, {ad_user, ADUser}];
split_active_directory_args(_Parts) ->
    [].
