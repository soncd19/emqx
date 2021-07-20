%%--------------------------------------------------------------------
%% Copyright (c) 2020 Arad ITC <info@arad-itc.org>.
%% Modify By Soncd <caodinsonbk202@gmail.com>
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_kafka_bridge).

-include_lib("emqx/include/emqx.hrl").

-export([load/1, unload/0]).

-define(APP, emqx_kafka_bridge).

%% Hooks functions
-export([on_client_connected/3, on_client_disconnected/4]).
%%-export([on_client_subscribe/3, on_client_unsubscribe/3]).
%%-export([on_session_created/3, on_session_resumed/3, on_session_terminated/3]).
%%-export([on_session_subscribed/4, on_session_unsubscribed/4]).
-export([on_message_publish/2, on_message_delivered/3, on_message_acked/3]).

%% Called when the plugin application start
load(Env) ->
    brod_init([Env]),
    emqx:hook('client.connected', fun ?MODULE:on_client_connected/3, [Env]),
    emqx:hook('client.disconnected', fun ?MODULE:on_client_disconnected/4, [Env]),
%%    emqx:hook('client.subscribe', fun ?MODULE:on_client_subscribe/3, [Env]),
%%    emqx:hook('client.unsubscribe', fun ?MODULE:on_client_unsubscribe/3, [Env]),
%%    emqx:hook('session.created', fun ?MODULE:on_session_created/3, [Env]),
%%    emqx:hook('session.resumed', fun ?MODULE:on_session_resumed/3, [Env]),
%%    emqx:hook('session.subscribed', fun ?MODULE:on_session_subscribed/4, [Env]),
%%    emqx:hook('session.unsubscribed', fun ?MODULE:on_session_unsubscribed/4, [Env]),
%%    emqx:hook('session.terminated', fun ?MODULE:on_session_terminated/3, [Env]),
    emqx:hook('message.publish', fun ?MODULE:on_message_publish/2, [Env]),
    emqx:hook('message.delivered', fun ?MODULE:on_message_delivered/3, [Env]),
    emqx:hook('message.acked', fun ?MODULE:on_message_acked/3, [Env]).

%%emqx:hook('message.dropped', fun ?MODULE:on_message_dropped/3, [Env]).

%% Client is online

on_client_connected(#{clientid := ClientId, username := Username}, ConnInfo, _Env) ->
    io:format("client ~s, username: ~s, connected~n", [ClientId, Username]),
    % produce_kafka_payload(<<"event">>, Client),

    Action = <<"connected">>,
    [{_, Topic}] = ets:lookup(topic_table, kafka_connected_topic),
    Payload = [{action, Action},
        {client_id, ClientId},
        {node, node()},
        {username, Username},
        {connected_at, maps:get(connected_at, ConnInfo)}],
    produce_kafka_payload(Topic, Username, Payload, _Env),
    ok.

%% Client disconnected
on_client_disconnected(#{clientid := ClientId, username := Username}, Reason, ConnInfo, _Env) ->
    io:format("KAFKA Client(~s), Username(~s) disconnected, reason_code: ~w~n", [ClientId, Username, stringfy(maybe(Reason))]),
    Action = <<"disconnected">>,
    Payload = [{action, Action},
        {client_id, ClientId},
        {node, node()},
        {username, Username},
        {reason, stringfy(maybe(Reason))},
        {disconnected_at, maps:get(connected_at, ConnInfo)}],
    [{_, Topic}] = ets:lookup(topic_table, kafka_disconnected_topic),
    produce_kafka_payload(Topic, Username, Payload, _Env),
    ok.

%% Client subscription topic
%%on_client_subscribe(#{clientid := ClientId}, RawTopicFilters, _Env) ->
%%    io:format("KAFKA Client(~s) will subscribe: ~p~n", [ClientId, RawTopicFilters]),
%%    {ok, RawTopicFilters}.

%% Client unsubscribes topic
%%on_client_unsubscribe(#{clientid := ClientId}, RawTopicFilters, _Env) ->
%%    io:format("KAFKA Client(~s) unsubscribe ~p~n", [ClientId, RawTopicFilters]),
%%    {ok, RawTopicFilters}.

%% Session creation
%%on_session_created(#{client_id := ClientId}, SessAttrs, _Env) ->
%%    io:format("KAFKA Session(~s) created: ~p~n", [ClientId, SessAttrs]).
%%    Now = erlang:timestamp(),
%%    Username = proplists:get_value(username, SessAttrs),
%%    Payload = [{client_id, ClientId}, {username, Username}, {node, node()},  {ts, emqx_time:now_secs(Now)}],
%%    Connected = proplists:get_value(connected, _Env),
%%    produce_kafka_payload(Connected, Username, Payload, _Env).

%% Session resume
%%on_session_resumed(#{client_id := ClientId}, SessAttrs, _Env) ->
%%    io:format("KAFKA Session(~s) resumed: ~p~n", [ClientId, SessAttrs]).

%% After the session is subscribed
%%on_session_subscribed(#{client_id := ClientId, username := Username}, Topic, SubOpts, _Env) ->
%%    io:format("KAFKA Session(~s), Username(~s) subscribe ~s with subopts: ~p~n", [ClientId, Username, Topic, SubOpts]).
%%    Now = erlang:timestamp(),
%%    Payload = [{client_id, ClientId}, {node, node()}, {username, Username}, {topic, Topic}, {ts, emqx_time:now_secs(Now)}],
%%    Subscribed = proplists:get_value(subscribed, _Env),
%%    produce_kafka_payload(Subscribed, Username, Payload, _Env).

%% After the session unsubscribes the topic
%%on_session_unsubscribed(#{client_id := ClientId}, Topic, Opts, _Env) ->
%%    io:format("KAFKA Session(~s) unsubscribe ~s with opts: ~p~n", [ClientId, Topic, Opts]).

%% Session terminated
%%on_session_terminated(#{client_id := ClientId}, ReasonCode, _Env) ->
%%    io:format("KAFKA Session(~s) terminated: ~p.", [ClientId, ReasonCode]).

%% Transform message and return
on_message_publish(Message = #message{topic = <<"$SYS/", _/binary>>}, _Env) ->
    {ok, Message};

on_message_publish(Message = #message{id = MsgId,
    qos = Qos,
    from = From,
    topic = Topic,
    payload = Payload,
    timestamp = Time
}, _Env) ->
    io:format("KAFKA publish MsgId(~s) ~s~n", [MsgId, emqx_message:format(Message)]),
    MP = proplists:get_value(regex, _Env),
    case re:run(Topic, MP, [{capture, all_but_first, list}]) of
        nomatch -> io:format("KAFKA Topic nomatch ~s ~p ~n", [Topic, MP]), {ok, Message};
        {match, Captured} -> [Type, ProductId, DevKey | Fix] = Captured,
            Topics = proplists:get_value(topic, _Env),
            case proplists:get_value(Type, Topics) of
                undefined -> io:format("KAFKA publish no match topic ~s", [Type]);
                ProduceTopic ->
                    Key = iolist_to_binary([ProductId, "_", DevKey, "_", Fix]),
                    Partition = proplists:get_value(partition, _Env),
                    Msg = [{client_id, From}, {node, node()}, {qos, Qos}, {payload, Payload}, {topic, Topic}, {ts, Time}],
                    {ok, MessageBody} = emqx_json:safe_encode(Msg),
                    MsgPayload = iolist_to_binary(MessageBody),
                    ok = brod:produce_sync(brod_client_1, ProduceTopic, getPartiton(Key, Partition), Key, MsgPayload)
            end,
            {ok, Message}
    end.

%% MQTT message delivery
on_message_delivered(#{client_id := ClientId}, Message, _Env) ->
    io:format("KAFKA Delivered message to client(~s): ~s~n", [ClientId, emqx_message:format(Message)]),
    {ok, Message}.

%% MQTT message receipt
on_message_acked(#{client_id := ClientId}, Message, _Env) ->
    io:format("KAFKA Session(~s) acked message: ~s~n", [ClientId, emqx_message:format(Message)]),
    {ok, Message}.

%% MQTT message discarded
%%on_message_dropped(_By, #message{topic = <<"$SYS/", _/binary>>}, _Env) ->
%%    ok;
%%on_message_dropped(#{node := Node}, Message, _Env) ->
%%    io:format("KAFKA Message dropped by node ~s: ~s~n", [Node, emqx_message:format(Message)]);
%%on_message_dropped(#{client_id := ClientId}, Message, _Env) ->
%%    io:format("KAFKA Message dropped by client ~s: ~s~n", [ClientId, emqx_message:format(Message)]).

brod_init(_Env) ->
    {ok, _} = application:ensure_all_started(brod),
    {ok, BootstrapBroker} = application:get_env(?APP, broker),
    {ok, ClientConfig} = application:get_env(?APP, client),
    ok = brod:start_client(BootstrapBroker, brod_client_1, ClientConfig),

    {ok, Connected} = application:get_env(emqx_kafka_bridge, connected),
    {ok, Disconnected} = application:get_env(emqx_kafka_bridge, disconnected),
    {ok, Subscribed} = application:get_env(emqx_kafka_bridge, subscribed),
    {ok, Unsubscribe} = application:get_env(emqx_kafka_bridge, unsubscribe),

    ets:new(topic_table, [named_table, protected, set, {keypos, 1}]),
    ets:insert(topic_table, {kafka_connected_topic, Connected}),
    ets:insert(topic_table, {kafka_disconnected_topic, Disconnected}),
    ets:insert(topic_table, {kafka_subscribe_topic, Subscribed}),
    ets:insert(topic_table, {kafka_unsubscribe_topic, Unsubscribe}),

    io:format("KAFKA Init EMQX-Kafka-Bridge with ~p~n", [BootstrapBroker]).

getPartiton(Key, Partitions) ->
    <<_Fix:120, Match:8>> = crypto:hash(md5, Key),
    %%io:format("get partition with Fix ~s~n", [Fix]),
    abs(Match) rem Partitions.

%% Called when the plugin application stop
unload() ->
    emqx:unhook('client.connected', fun ?MODULE:on_client_connected/3),
    emqx:unhook('client.disconnected', fun ?MODULE:on_client_disconnected/4),
%%    emqx:unhook('client.subscribe', fun ?MODULE:on_client_subscribe/3),
%%    emqx:unhook('client.unsubscribe', fun ?MODULE:on_client_unsubscribe/3),
%%    emqx:unhook('session.created', fun ?MODULE:on_session_created/3),
%%    emqx:unhook('session.resumed', fun ?MODULE:on_session_resumed/3),
%%    emqx:unhook('session.subscribed', fun ?MODULE:on_session_subscribed/4),
%%    emqx:unhook('session.unsubscribed', fun ?MODULE:on_session_unsubscribed/4),
%%    emqx:unhook('session.terminated', fun ?MODULE:on_session_terminated/3),
    emqx:unhook('message.publish', fun ?MODULE:on_message_publish/2),
    emqx:unhook('message.delivered', fun ?MODULE:on_message_delivered/3),
    emqx:unhook('message.acked', fun ?MODULE:on_message_acked/3).
%%    emqx:unhook('message.dropped', fun ?MODULE:on_message_dropped/3).

produce_kafka_payload(Topic, Username, Message, _Env) ->
    {ok, MessageBody} = emqx_json:safe_encode(Message),
%%    MessageBody64 = base64:encode_to_string(MessageBody),
    Payload = iolist_to_binary(MessageBody),
    Partition = proplists:get_value(partition, _Env),
%%    Key = iolist_to_binary(Username),
%%    io:format("produce_kafka_payload with topic ~s, Payload ~s~n", [Topic, Payload]),
    brod:produce_sync(brod_client_1, list_to_binary(Topic), getPartiton(Username, Partition), Username, Payload).

stringfy(Term) when is_binary(Term) ->
    Term;
stringfy(Term) when is_atom(Term) ->
    atom_to_binary(Term, utf8);
stringfy(Term) ->
    unicode:characters_to_binary((io_lib:format("~0p", [Term]))).

maybe(undefined) -> null;
maybe(Str) -> Str.
