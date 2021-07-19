%%--------------------------------------------------------------------
%% Copyright (c) 2015-2017 Feng Lee <feng@emqtt.io>.
%%
%% Modified by SonCD <caodinhsonbk202@gmail.com>
%%
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

-include("emqx_kafka_bridge.hrl").

-include_lib("emqx/include/emqx.hrl").

-export([load/1, unload/0]).

%% Hooks functions

-export([on_client_connected/4, on_client_disconnected/3, on_client_authenticate/3, on_client_check_acl/5]).

% -export([on_client_subscribe/4, on_client_unsubscribe/4]).

% -export([on_session_created/3, on_session_subscribed/4, on_session_unsubscribed/4, on_session_terminated/4]).

-export([on_message_publish/2, on_message_delivered/3, on_message_acked/3]).


%% Called when the plugin application start
load(Env) ->
  ekaf_init([Env]),
  emqx:hook('client.connected', fun ?MODULE:on_client_connected/4, [Env]),
  emqx:hook('client.disconnected', fun ?MODULE:on_client_disconnected/3, [Env]),
  emqx:hook('message.publish', fun ?MODULE:on_message_publish/2, [Env]),
  emqx:hook('message.delivered', fun ?MODULE:on_message_delivered/3, [Env]),
  emqx:hook('message.acked', fun ?MODULE:on_message_acked/3, [Env]),
  emqx:hook('client.authenticate', fun ?MODULE:on_client_authenticate/3, [Env]),
  emqx:hook('client.check_acl', fun ?MODULE:on_client_check_acl/5, [Env]).

on_client_connected(#{client_id := ClientId, username := Username}, _ConnAck, _ConnInfo, _Env) ->
  io:format("client ~s connected, connack: ~w~n", [ClientId, _ConnAck]),
  % produce_kafka_payload(<<"event">>, Client),

  Action = <<"connected">>,
  Now = erlang:timestamp(),
  [{_, Topic}] = ets:lookup(topic_table, kafka_connected_topic),
  Payload = [{action, Action}, {device_id, ClientId}, {username, Username}, {ts, emqx_time:now_secs(Now)}],
  %{ok, Event} = format_event(Payload),
  io:format("client connected"),
  produce_kafka_payload(Topic, Payload),
  ok.

on_client_authenticate(_ClientInfo = #{clientid := ClientId}, Result, _Env) ->
  io:format("Client(~s) authenticate, Result:~n~p~n", [ClientId, Result]),
  {ok, Result}.

on_client_check_acl(_ClientInfo = #{clientid := ClientId}, Topic, PubSub, Result, _Env) ->
  io:format("Client(~s) check_acl, PubSub:~p, Topic:~p, Result:~p~n",
    [ClientId, PubSub, Topic, Result]),
  {ok, Result}.

on_client_disconnected(#{client_id := ClientId, username := Username}, _Reason, _Env) ->
  % io:format("client ~s disconnected, reason: ~w~n", [ClientId, Reason]),
  % produce_kafka_payload(<<"event">>, _Client),

  Action = <<"disconnected">>,
  Now = erlang:timestamp(),
  [{_, Topic}] = ets:lookup(topic_table, kafka_disconnected_topic),
  Payload = [{action, Action}, {device_id, ClientId}, {username, Username}, {ts, emqx_time:now_secs(Now)}],
  %{ok, Event} = format_event(Payload),
  produce_kafka_payload(Topic, Payload),
  ok.

%% transform message and return
on_message_publish(Message = #message{topic = <<"$SYS/", _/binary>>}, _Env) ->
  {ok, Message};

on_message_publish(Message, _Env) ->
  %%io:format("Publish message ~s~n", [emqx_message:format(Message)]),
  [{_, Topic}] = ets:lookup(topic_table, kafka_publish_topic),
  {ok, Payload} = format_payload(Message),
  %io:format("Publish message to kafka ~n"),
  produce_kafka_payload(Topic, Payload),
  {ok, Message}.

on_message_delivered(#{}, Message, _Env) ->
  % io:format("delivered to client(~s/~s): ~s~n", [Username, ClientId, emqttd_message:format(Message)]),
  {ok, Message}.

on_message_acked(#{}, Message, _Env) ->
  % io:format("client(~s/~s) acked: ~s~n", [Username, ClientId, emqttd_message:format(Message)]),
  {ok, Message}.

ekaf_init(_Env) ->
  {ok, BrokerValues} = application:get_env(emqx_kafka_bridge, broker),
  KafkaHost = proplists:get_value(host, BrokerValues),
  KafkaPort = proplists:get_value(port, BrokerValues),
  KafkaPartitionStrategy = proplists:get_value(partitionstrategy, BrokerValues),
  KafkaPartitionWorkers = proplists:get_value(partitionworkers, BrokerValues),
  KafkaPublishTopic = proplists:get_value(publishtopic, BrokerValues),
  KafkaConnectedTopic = proplists:get_value(connectedtopic, BrokerValues),
  KafkaDisconnectedTopic = proplists:get_value(disconnectedtopic, BrokerValues),
  KafkaSubscribeTopic = proplists:get_value(subscribetopic, BrokerValues),
  KafkaUnsubscribeTopic = proplists:get_value(unsubscribetopic, BrokerValues),
  KafkaDeliveredTopic = proplists:get_value(deliveredtopic, BrokerValues),

  application:set_env(ekaf, ekaf_bootstrap_broker, {KafkaHost, list_to_integer(KafkaPort)}),
  application:set_env(ekaf, ekaf_partition_strategy, list_to_atom(KafkaPartitionStrategy)),
  application:set_env(ekaf, ekaf_per_partition_workers, KafkaPartitionWorkers),
  application:set_env(ekaf, ekaf_buffer_ttl, 10),
  application:set_env(ekaf, ekaf_max_downtime_buffer_size, 5),

  ets:new(topic_table, [named_table, protected, set, {keypos, 1}]),
  % ets:insert(topic_table, {kafka_payload_topic, KafkaPayloadTopic}),
  % ets:insert(topic_table, {kafka_event_topic, KafkaEventTopic}),
  ets:insert(topic_table, {kafka_publish_topic, KafkaPublishTopic}),
  ets:insert(topic_table, {kafka_connected_topic, KafkaConnectedTopic}),
  ets:insert(topic_table, {kafka_disconnected_topic, KafkaDisconnectedTopic}),
  ets:insert(topic_table, {kafka_subscribe_topic, KafkaSubscribeTopic}),
  ets:insert(topic_table, {kafka_unsubscribe_topic, KafkaUnsubscribeTopic}),
  ets:insert(topic_table, {kafka_delivered_topic, KafkaDeliveredTopic}),

  % {ok, _} = application:ensure_all_started(kafkamocker),
  {ok, _} = application:ensure_all_started(gproc),
  % {ok, _} = application:ensure_all_started(ranch),
  {ok, _} = application:ensure_all_started(ekaf),
  io:format("start Test ekaf ~s~n", [ok]).

%%ekaf_get_topic() ->
%%  {ok, Topic} = application:get_env(ekaf, ekaf_bootstrap_topics),
%%  Topic.


format_payload(Message) ->
  Username = emqx_message:get_header(username, Message),
  Deviceid = Message#message.from,
  %%Ts = Message#message.timestamp,

  Topic = Message#message.topic,
  Tail = string:right(binary_to_list(Topic), 4),
  RawType = string:equal(Tail, <<"_raw">>),
  %%io:format("Tail= ~s , RawType= ~s~n", [Tail, RawType]),

  MsgPayload = Message#message.payload,
  %%io:format("MsgPayload : ~s~n", [MsgPayload]),
  MsgPayloads = MsgPayload,
  if
    RawType == true ->
      MsgPayloads = list_to_binary(base64:encode_to_string(MsgPayload));
    RawType == false ->
      MsgPayloads = MsgPayload
  end,
  %%io:format("format message to kafka ok ~s~n", [MsgPayloads]),
  Payload = [{action, message_publish},
    {deviceid, Deviceid},
    {username, Username},
    {topic, Topic},
    {payload, MsgPayloads},
    {ts, emqx_time:now_ms()}],
  % io:format("format Payload before send kafka ~s~n", [Payload]),
  {ok, Payload}.


%% Called when the plugin application stop
unload() ->
  emqx:unhook('client.connected', fun ?MODULE:on_client_connected/4),
  emqx:unhook('client.disconnected', fun ?MODULE:on_client_disconnected/3),
  emqx:unhook('client.authenticate', {?MODULE, on_client_authenticate}),
  emqx:unhook('client.check_acl', {?MODULE, on_client_check_acl}),
  % emqx:unhook('client.subscribe', fun ?MODULE:on_client_subscribe/4),
  % emqx:unhook('client.unsubscribe', fun ?MODULE:on_client_unsubscribe/4),
  % emqx:unhook('session.subscribed', fun ?MODULE:on_session_subscribed/4),
  % emqx:unhook('session.unsubscribed', fun ?MODULE:on_session_unsubscribed/4),
  emqx:unhook('message.publish', fun ?MODULE:on_message_publish/2),
  emqx:unhook('message.delivered', fun ?MODULE:on_message_delivered/3),
  emqx:unhook('message.acked', fun ?MODULE:on_message_acked/3).

produce_kafka_payload(Topic, Message) ->
  %%Topic = ekaf_get_topic(),
  io:format("Publish message to kafka with topic ~s~n", [Topic]),
  {ok, MessageBody} = emqx_json:safe_encode(Message),

  % MessageBody64 = base64:encode_to_string(MessageBody),
  Payload = iolist_to_binary(MessageBody),
  io:format("Publish message to kafka with payload ~s~n", [Payload]),
  ok = ekaf:produce_async_batched(list_to_binary(Topic), Payload),
  io:format("send message to kafka: ~s~n", [ok]),
  ok.
