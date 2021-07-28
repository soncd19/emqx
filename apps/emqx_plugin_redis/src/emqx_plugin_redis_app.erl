%%%-------------------------------------------------------------------
%%% @author soncd
%%% @copyright (C) 2021, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 28. Jul 2021
%%%-------------------------------------------------------------------

-module(emqx_plugin_redis_app).

-behaviour(application).

-include("emqx_plugin_redis.hrl").

-emqx_plugin(?MODULE).

-export([start/2
    , stop/1
]).

start(_StartType, _StartArgs) ->
    {ok, Sup} = emqx_plugin_redis_sup:start_link(),
    _ = if_cmd_enabled(connect_cmd, fun load_connect_hook/1),
    _ = if_cmd_enabled(disconnect_cmd, fun load_disconnect_hook/1),
    {ok, Sup}.

stop(_State) ->
    emqx:unhook('client.connected', fun emqx_plugin_redis:on_client_connected/3),
    emqx:unhook('client.disconnected', fun emqx_plugin_redis:on_client_disconnected/4),
    eredis_cluster:stop_pool(?APP).

load_connect_hook(ConnectCmd) ->
    {ok, Timeout} = application:get_env(?APP, query_timeout),
    Type = proplists:get_value(type, application:get_env(?APP, server, [])),
    Config = #{connect_cmd => ConnectCmd,
        timeout => Timeout,
        type => Type,
        pool => ?APP},
    emqx:hook('client.connected', fun emqx_plugin_redis:on_client_connected/3, [Config]).

load_disconnect_hook(DisconnectCmd) ->
    {ok, Timeout} = application:get_env(?APP, query_timeout),
    Type = proplists:get_value(type, application:get_env(?APP, server, [])),
    Config = #{disconnect_cmd => DisconnectCmd,
        timeout => Timeout,
        type => Type,
        pool => ?APP},
    emqx:hook('client.disconnected', fun emqx_plugin_redis:on_client_disconnected/4, [Config]).

if_cmd_enabled(Par, Fun) ->
    case application:get_env(?APP, Par) of
        {ok, Cmd} -> Fun(Cmd);
        undefined -> ok
    end.
