-module(binary_parser_SUITE).

-compile(export_all).

-export([
         ]).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Common Test callbacks
%%%===================================================================

all() ->
    [
     {group, tests}
    ].


all_tests() ->
    [
     roundtrip,
     array_with_extra_input,
     unsupported_type,
     server_mode_symbolic_body_descriptors,
     server_mode_body_descriptor_prefix_collision
    ].

groups() ->
    [
     {tests, [parallel], all_tests()}
    ].

roundtrip(_Config) ->
    Terms = [
             null,
             {described,
              {symbol, <<"URL">>},
              {utf8, <<"http://example.org/hello-world">>}},
             {described,
              {symbol, <<"URL">>},
              {binary, <<"https://rabbitmq.com">>}},
             %% "The descriptor portion of a described format code is itself
             %% any valid AMQP encoded value, including other described values." [1.2]
             {described,
              {described,
               {symbol, <<"inner constructor">>},
               {binary, <<"inner value">>}},
              {binary, <<"outer value">>}},
             {array, ubyte, [{ubyte, 1}, {ubyte, 255}]},
             true,
             {list, [{utf8, <<"hi">>},
                     {described,
                      {symbol, <<"URL">>},
                      {utf8, <<"http://example.org/hello-world">>}}
                    ]},
             {list, [{int, 123},
                     {array, int, [{int, 1}, {int, 2}, {int, 3}]}
                    ]},
             {map, [
                    {{utf8, <<"key1">>}, {utf8, <<"value1">>}},
                    {{utf8, <<"key2">>}, {int, 33}}
                   ]},
             {array, {described, {utf8, <<"URL">>}, utf8}, []},
             false
            ],

    Bin = lists:foldl(
            fun(T, Acc) ->
                    B = iolist_to_binary(amqp10_binary_generator:generate(T)),
                    <<Acc/binary, B/binary>>
            end, <<>>, Terms),

    ?assertEqual(Terms, amqp10_binary_parser:parse_many(Bin, [])).

array_with_extra_input(_Config) ->
    Bin = <<83,16,192,85,10,177,0,0,0,1,48,161,12,114,97,98,98,105,116, 109,113,45,98,111,120,112,255,255,0,0,96,0,50,112,0,0,19,136,163,5,101,110,45,85,83,224,14,2,65,5,102,105,45,70,73,5,101,110,45,85,83,64,64,193,24,2,163,20,68,69,70,69,78,83,73,67,83,46,84,69,83,84,46,83,85,73,84,69,65>>,

    Expected = {failed_to_parse_array_extra_input_remaining,
                %% element type, input, accumulated result
                65, <<105,45,70,73,5,101,110,45,85,83>>, [true,true]},

    ?assertExit(Expected, amqp10_binary_parser:parse_many(Bin, [])).

unsupported_type(_Config) ->
    UnsupportedType = 16#02,
    Bin = <<UnsupportedType, "hey">>,
    Expected = {primitive_type_unsupported, UnsupportedType, {position, 0}},
    ?assertThrow(Expected, amqp10_binary_parser:parse_many(Bin, [])).

%% A symbolic body descriptor of the exact registered length is classified as
%% the corresponding standard body section in server_mode.
server_mode_symbolic_body_descriptors(_Config) ->
    Data8 = <<0, 16#a3, 16, "amqp:data:binary", 16#a0, 1, "x">>,
    Seq8 = <<0, 16#a3, 23, "amqp:amqp-sequence:list", 16#45>>,
    Value8 = <<0, 16#a3, 17, "amqp:amqp-value:*", 16#a1, 1, "x">>,
    ?assertEqual([{{pos, 0}, {body, 16#75}}],
                 amqp10_binary_parser:parse_many(Data8, [server_mode])),
    ?assertEqual([{{pos, 0}, {body, 16#76}}],
                 amqp10_binary_parser:parse_many(Seq8, [server_mode])),
    ?assertEqual([{{pos, 0}, {body, 16#77}}],
                 amqp10_binary_parser:parse_many(Value8, [server_mode])),
    %% The sym32 forms must be classified identically.
    Data32 = <<0, 16#b3, 16:32, "amqp:data:binary", 16#a0, 1, "x">>,
    Seq32 = <<0, 16#b3, 23:32, "amqp:amqp-sequence:list", 16#45>>,
    Value32 = <<0, 16#b3, 17:32, "amqp:amqp-value:*", 16#a1, 1, "x">>,
    ?assertEqual([{{pos, 0}, {body, 16#75}}],
                 amqp10_binary_parser:parse_many(Data32, [server_mode])),
    ?assertEqual([{{pos, 0}, {body, 16#76}}],
                 amqp10_binary_parser:parse_many(Seq32, [server_mode])),
    ?assertEqual([{{pos, 0}, {body, 16#77}}],
                 amqp10_binary_parser:parse_many(Value32, [server_mode])).

server_mode_body_descriptor_prefix_collision(_Config) ->
    %% Well-formed but unknown descriptor "amqp:data:binary@" (length 17).
    Collision8 = <<0, 16#a3, 17, "amqp:data:binary", $@, 16#a0, 3, "abc">>,
    ?assertEqual(
       [{described, {symbol, <<"amqp:data:binary@">>}, {binary, <<"abc">>}}],
       amqp10_binary_parser:parse_many(Collision8, [server_mode])),

    %% The same collision via the sym32 constructor.
    Collision32 = <<0, 16#b3, 17:32, "amqp:data:binary", $@, 16#a0, 3, "abc">>,
    ?assertEqual(
       [{described, {symbol, <<"amqp:data:binary@">>}, {binary, <<"abc">>}}],
       amqp10_binary_parser:parse_many(Collision32, [server_mode])),

    %% A prefix collision on the amqp-value descriptor.
    ValueCollision = <<0, 16#a3, 18, "amqp:amqp-value:*!", 16#a1, 1, "x">>,
    ?assertEqual(
       [{described, {symbol, <<"amqp:amqp-value:*!">>}, {utf8, <<"x">>}}],
       amqp10_binary_parser:parse_many(ValueCollision, [server_mode])).
