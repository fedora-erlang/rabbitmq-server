%% This Source Code Form is subject to the terms of the Mozilla Public
%% License, v. 2.0. If a copy of the MPL was not distributed with this
%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%
%% Copyright (c) 2007-2025 Broadcom. All Rights Reserved.
%% The term “Broadcom” refers to Broadcom Inc. and/or its subsidiaries. All rights reserved.
%%


-module(rabbit_access_control_SUITE).

-compile(export_all).

-include_lib("eunit/include/eunit.hrl").
-include_lib("rabbit_common/include/rabbit.hrl").

%%%===================================================================
%%% Common Test callbacks
%%%===================================================================


all() ->
    [{group, tests}].

%% replicate eunit like test resolution
all_tests() ->
    [F
     || {F, _} <- ?MODULE:module_info(functions),
        re:run(atom_to_list(F), "_test$") /= nomatch].

groups() ->
    [{tests, [], all_tests()}].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

init_per_group(_Group, Config) ->
    Config.

end_per_group(_Group, _Config) ->
    ok.

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    meck:unload(),
    ok.

expiry_timestamp_test(_) ->
    %% test rabbit_access_control:expiry_timestamp/1 returns the earliest expiry time
    Now = os:system_time(seconds),
    BeforeNow = Now - 60,
    %% returns now
    ok = meck:new(rabbit_expiry_backend, [non_strict]),
    meck:expect(rabbit_expiry_backend, expiry_timestamp, fun (_) -> Now end),
    %% return a bit before now (so the earliest expiry time)
    ok = meck:new(rabbit_earlier_expiry_backend, [non_strict]),
    meck:expect(rabbit_earlier_expiry_backend, expiry_timestamp, fun (_) -> BeforeNow end),
    %% return 'never' (no expiry)
    ok = meck:new(rabbit_no_expiry_backend, [non_strict]),
    meck:expect(rabbit_no_expiry_backend, expiry_timestamp, fun (_) -> never end),

    %% never expires
    User1 = #user{authz_backends = [{rabbit_no_expiry_backend, unused}]},
    ?assertEqual(never, rabbit_access_control:expiry_timestamp(User1)),

    %% returns the result from the backend that expires
    User2 = #user{authz_backends = [{rabbit_expiry_backend, unused},
                                    {rabbit_no_expiry_backend, unused}]},
    ?assertEqual(Now, rabbit_access_control:expiry_timestamp(User2)),

    %% returns earliest expiry time
    User3 = #user{authz_backends = [{rabbit_expiry_backend, unused},
                                    {rabbit_earlier_expiry_backend, unused},
                                    {rabbit_no_expiry_backend, unused}]},
    ?assertEqual(BeforeNow, rabbit_access_control:expiry_timestamp(User3)),

    %% returns earliest expiry time
    User4 = #user{authz_backends = [{rabbit_earlier_expiry_backend, unused},
                                    {rabbit_expiry_backend, unused},
                                    {rabbit_no_expiry_backend, unused}]},
    ?assertEqual(BeforeNow, rabbit_access_control:expiry_timestamp(User4)),

    %% returns earliest expiry time
    User5 = #user{authz_backends = [{rabbit_no_expiry_backend, unused},
                                    {rabbit_earlier_expiry_backend, unused},
                                    {rabbit_expiry_backend, unused}]},
    ?assertEqual(BeforeNow, rabbit_access_control:expiry_timestamp(User5)),

    %% returns earliest expiry time
    User6 = #user{authz_backends = [{rabbit_no_expiry_backend, unused},
                                    {rabbit_expiry_backend, unused},
                                    {rabbit_earlier_expiry_backend, unused}]},
    ?assertEqual(BeforeNow, rabbit_access_control:expiry_timestamp(User6)),

    %% returns the result from the backend that expires
    User7 = #user{authz_backends = [{rabbit_no_expiry_backend, unused},
                                    {rabbit_expiry_backend, unused}]},
    ?assertEqual(Now, rabbit_access_control:expiry_timestamp(User7)),
    ok.

%% A refresh must rebuild `#user.tags`. Without this a tag that the new
%% credential revoked, for example `impersonator`, would survive and still be
%% honoured by `check_user_id/2`.
update_state_rebuilds_tags_test(_) ->
    Mod = rabbit_refresh_backend,
    ok = meck:new(Mod, [non_strict]),
    meck:expect(Mod, expiry_timestamp, fun(_) -> os:system_time(seconds) + 60 end),
    %% This stands in for a refresh-capable backend. It returns a fresh tag set
    %% from the new credential, as OAuth's `update_state/2` does.
    meck:expect(Mod, update_state,
                fun(AuthUser, NewTags) ->
                        {ok, AuthUser#auth_user{tags = NewTags,
                                                impl = fun() -> NewTags end}}
                end),

    User = #user{username = <<"u">>,
                 tags = [impersonator, management],
                 authz_backends = [{Mod, unused}]},

    {ok, U1} = rabbit_access_control:update_state(User, [management]),
    ?assertEqual([management], U1#user.tags),
    ?assertNot(lists:member(impersonator, U1#user.tags)),

    %% A refresh to a credential with no tags clears them; keeping the old set
    %% here would leave impersonator behind.
    {ok, U2} = rabbit_access_control:update_state(User, []),
    ?assertEqual([], U2#user.tags),

    {ok, U3} = rabbit_access_control:update_state(User, [impersonator, management]),
    ?assert(lists:member(impersonator, U3#user.tags)),

    %% A backend without expiry is not refreshed and leaves the tags as they are.
    ok = meck:new(rabbit_static_backend, [non_strict]),
    meck:expect(rabbit_static_backend, expiry_timestamp, fun(_) -> never end),
    Static = #user{username = <<"u">>,
                   tags = [administrator],
                   authz_backends = [{rabbit_static_backend, unused}]},
    {ok, U4} = rabbit_access_control:update_state(Static, ignored),
    ?assertEqual([administrator], U4#user.tags),
    ok.
