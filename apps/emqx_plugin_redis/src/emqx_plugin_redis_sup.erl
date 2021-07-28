%%%-------------------------------------------------------------------
%%% @author soncd
%%% @copyright (C) 2021, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 28. Jul 2021
%%%-------------------------------------------------------------------

-module(emqx_plugin_redis_sup).

-include("emqx_plugin_redis.hrl").
-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, Server} = application:get_env(?APP, server),
    {ok, {{one_for_all, 10, 100}, pool_spec(Server)}}.

pool_spec(Server) ->
    Options = application:get_env(?APP, options, []),
    case proplists:get_value(type, Server) of
        cluster ->
            {ok, _} = eredis_cluster:start_pool(?APP, Server ++ Options),
            [];
        _ ->
            [ecpool:pool_spec(?APP, ?APP, emqx_plugin_redis_cli, Server ++ Options)]
    end.


