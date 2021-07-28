%%%-------------------------------------------------------------------
%%% @author soncd
%%% @copyright (C) 2021, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 28. Jul 2021
%%%-------------------------------------------------------------------
-module(emqx_plugin_redis_cli).

-behavior(ecpool_worker).

-include_lib("emqx/include/emqx.hrl").
-include_lib("emqx/include/logger.hrl").

-import(proplists, [get_value/2, get_value/3]).


%% API
-export([connect/1
    , q/5]).

connect(Opts) ->
    Sentinel = get_value(sentinel, Opts),
    Host = case Sentinel =:= "" of
               true -> get_value(host, Opts);
               false ->
                   _ = eredis_sentinel:start_link(get_value(server, Opts), get_value(options, Opts, [])),
                   "sentinel:" ++ Sentinel
           end,
    case eredis:start_link(Host,
        get_value(port, Opts, 6379),
        get_value(database, Opts, 0),
        get_value(password, Opts, ""),
        3000,
        5000,
        get_value(options, Opts, [])) of
        {ok, Pid} -> {ok, Pid};
        {error, Reason = {connection_error, _}} ->
            ?LOG(error, "[Redis] Can't connect to Redis server: Connection refused."),
            {error, Reason};
        {error, Reason = {authentication_error, _}} ->
            ?LOG(error, "[Redis] Can't connect to Redis server: Authentication failed."),
            {error, Reason};
        {error, Reason} ->
            ?LOG(error, "[Redis] Can't connect to Redis server: ~p", [Reason]),
            {error, Reason}
    end.

%% Redis Query.
-spec(q(atom(), atom(), string(), emqx_types:credentials(), timeout())
        -> {ok, undefined | binary() | list()} | {error, atom() | binary()}).
q(Pool, Type, CmdStr, Credentials, Timeout) ->
    Cmd = string:tokens(replvar(CmdStr, Credentials), " "),
    case Type of
        cluster -> eredis_cluster:q(Pool, Cmd);
        _ -> ecpool:with_client(Pool, fun(C) -> eredis:q(C, Cmd, Timeout) end)
    end.

replvar(Cmd, Credentials = #{clientid := ClientId, username := Username}) ->
    Message = [
        {client_id, ClientId},
        {username, Username},
        {node, node()},
        {connected_at, emqx_time:now_ms()}],
    {ok, MessageBody} = emqx_json:safe_encode(Message),
    Payload = iolist_to_binary(MessageBody),
    replvar(repl(repl(Cmd, "%info", Payload), "%c", ClientId), maps:remove(clientid, Credentials));

replvar(Cmd, Credentials = #{username := Username}) ->
    replvar(repl(Cmd, "%u", Username), maps:remove(username, Credentials));
replvar(Cmd, _) ->
    Cmd.

repl(S, _Var, undefined) ->
    S;
repl(S, Var, Val) ->
    NVal = re:replace(Val, "&", "\\\\&", [global, {return, list}]),
    re:replace(S, Var, NVal, [{return, list}]).
