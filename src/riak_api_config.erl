%% -------------------------------------------------------------------
%%
%% riak_api_config: Interface to configuration information
%%
%% Copyright (c) 2007-2012 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------
-module(riak_api_config).
-export([get_listeners/0,
         get_listeners/1]).

%% @doc Returns all listener specifications, grouped by protocol.
get_listeners() ->
    [ {Key, L} || Key <- [ pb ],
                  L = get_listeners(Key),
                  L /= [] ].

%% @doc Fetches listener specifications by protocol.
-spec get_listeners(Protocol::pb | http | https) -> [ {inet:ip_address(), inet:port_number()} ].
get_listeners(pb) ->
    DefaultListener = case {get_ip(), get_port()} of
                          {undefined, _} -> [];
                          {_, undefined} -> [];
                          {IP, Port} -> [{IP, Port}]
                      end,
    Listeners = app_helper:get_env(riak_api, pb, []) ++ DefaultListener,
    [ {I, P} || {I, P} <- Listeners ];
get_listeners(_) ->
    [].

%% @private
get_port() ->
    case app_helper:get_env(riak_api, pb_port) of
        undefined ->
            undefined;
        Port ->
            lager:warning("The config riak_api/pb_port has been"
                          " deprecated and will be removed. Use"
                          " riak_api/pb (IP/Port pairs) in the future."),
            Port
    end.

%% @private
get_ip() ->
    case app_helper:get_env(riak_api, pb_ip) of
        undefined ->
            undefined;
        IP ->
            lager:warning("The config riak_api/pb_ip has been"
                          " deprecated and will be removed. Use"
                          " riak_api/pb (IP/Port pairs) in the future."),
            IP
    end.

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-compile(export_all).

listeners_test_() ->
    {foreach,
     fun() ->
             application:load(riak_api),
             app_helper:get_env(riak_api, pb, [{"127.0.0.1", 8087}])
     end,
     fun(OldListeners) ->
             application:set_env(riak_api, pb, OldListeners),
             application:unset_env(riak_api, pb_ip),
             application:unset_env(riak_api, pb_port)
     end,
     [
      {"old config keys get upgraded",
       fun() ->
               application:unset_env(riak_api, pb),
               application:set_env(riak_api, pb_ip, "127.0.0.1"),
               application:set_env(riak_api, pb_port, 10887),
               ?assertEqual([{"127.0.0.1", 10887}], get_listeners())
       end},
      {"missing old IP config key disables listener",
       fun() ->
               application:unset_env(riak_api, pb),
               %% application:set_env(riak_api, pb_ip, "127.0.0.1"),
               application:set_env(riak_api, pb_port, 10887),
               ?assertEqual([], get_listeners())
       end},
      {"missing old Port config key disables listener",
       fun() ->
               application:unset_env(riak_api, pb),
               application:set_env(riak_api, pb_ip, "127.0.0.1"),
               %% application:set_env(riak_api, pb_port, 10887),
               ?assertEqual([], get_listeners())
       end},
      {"bad configs are ignored",
       fun() ->
              application:set_env(riak_api, pb, [{"0.0.0.0", 8087}, badjuju]),
               ?assertEqual([{"0.0.0.0", 8087}], get_listeners())
       end}]}.

-endif.
