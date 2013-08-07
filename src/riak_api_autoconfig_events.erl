%% -------------------------------------------------------------------
%%
%% riak_api_autoconfig_events: notify clients of discovery changes
%%
%% Copyright (c) 2007-2010 Basho Technologies, Inc.  All Rights Reserved.
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
-module(riak_api_autoconfig_events).

-behaviour(gen_event).

%% API
-export([start_link/0, add_handler/1, notify/1]).

%% gen_event callbacks
-export([init/1, handle_event/2, handle_call/2, 
         handle_info/2, terminate/2, code_change/3]).

-define(SERVER, ?MODULE). 

-record(state, {client}).

start_link() ->
    gen_event:start_link({local, ?SERVER}).

add_handler(Pid) ->
    gen_event:add_sup_handler(?SERVER, ?MODULE, [Pid]).

notify(NewConfig) ->
    gen_event:notify(?SERVER, {new_config, NewConfig}).

%%%===================================================================
%%% gen_event callbacks
%%%===================================================================

init([Pid]) ->
    {ok, #state{client=Pid}}.

handle_event({new_config, NewConfig}, State=#state{client=Pid}) ->
    Pid ! {new_config, NewConfig},
    {ok, State}.

handle_call(_Request, State) ->
    Reply = ok,
    {ok, Reply, State}.

handle_info(_Info, State) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
