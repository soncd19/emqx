%%%-------------------------------------------------------------------
%%% @author soncd
%%% @copyright (C) 2021, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 28. Jul 2021
%%%-------------------------------------------------------------------

-module(emqx_plugin_redis).

-include("emqx_plugin_redis.hrl").
-include_lib("emqx/include/emqx.hrl").
-include_lib("emqx/include/logger.hrl").

%% Client Lifecircle Hooks
-export([on_client_connected/3
    , on_client_disconnected/4
]).


%%--------------------------------------------------------------------
%% Process client online, offline
%%--------------------------------------------------------------------

on_client_connected(ClientInfo = #{clientid := ClientId}, ConnInfo,
    #{connect_cmd := ConnectCmd,
        timeout := Timeout,
        type := Type,
        pool := Pool}) ->
    ?LOG(info, "Client(~s) connected, ClientInfo:~n~p~n, ConnInfo:~n~p~n",
        [ClientId, ClientInfo, ConnInfo]),
    case emqx_plugin_redis_cli:q(Pool, Type, ConnectCmd, ClientInfo, Timeout) of
        {ok, <<"OK">>} ->
            ok;
        {error, Reason} ->
            ?LOG(error, "[Redis] client connected error: ~p", [Reason]),
            ok
    end.


on_client_disconnected(ClientInfo = #{clientid := ClientId}, ReasonCode, ConnInfo,
    #{disconnect_cmd := DisconnectCmd,
        timeout := Timeout,
        type := Type,
        pool := Pool}) ->
    ?LOG(info, "Client(~s) disconnected due to ~p, ClientInfo:~n~p~n, ConnInfo:~n~p~n",
        [ClientId, ReasonCode, ClientInfo, ConnInfo]),
    case emqx_plugin_redis_cli:q(Pool, Type, DisconnectCmd, ClientInfo, Timeout) of
        {ok, <<"1">>} ->
            ok;
        {ok, <<"0">>} ->
            ?LOG(info, "[emqx eedis] Client(~s) not exits on redis", [ClientId]),
            ok;
        {error, Reason} ->
            ?LOG(error, "[Redis] client disconnect error: ~p", [Reason]),
            ok
    end.




