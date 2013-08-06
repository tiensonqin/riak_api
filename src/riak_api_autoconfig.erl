%% -------------------------------------------------------------------
%%
%% riak_api_autoconfig: advertise and manage client-interface discovery
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
-module(riak_api_autoconfig).
-behaviour(gen_fsm).

-define(MAP, riak_dt_rwmap).
-define(REGISTER, riak_dt_lwwreg).
-define(LOCAL_KEY, {node(), ?REGISTER}).
-define(PEER_KEY(N), {N, ?REGISTER}).

-record(state, {
          actor = riak_core_nodeid:get(),
          config,
          members,
          timer
         }).

%% Public API
-export([start_link/0, get/0]).

%% gen_fsm API
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3,
         terminate/3, code_change/4]).

%% states
-export([wait_for_capable/2, wait_for_capable/3,
         normal/2, normal/3]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, []).

get() ->
    gen_fsm:sync_send_all_state_event(?MODULE, get_config).

%%---------------------------
%% gen_fsm callbacks and states
%%---------------------------
init([]) ->
    T = schedule_tick(0),
    {ok, wait_for_capable, #state{timer=T}}.


wait_for_capable({timeout, T, tick}, #state{timer=T}=State) ->
    T1 = schedule_tick(),
    case is_capable() of
        false ->
            {next_state, wait_for_capable, State#state{timer=T1}};
        true ->
            %% We assume that if discovery is on, that the broadcast
            %% system exists and is in-use.

            {next_state, normal, State#state{config=store_config(update_my_config(State)),
                                             members=get_members(),
                                             timer=T1}}
    end.

wait_for_capable(_Event, _From, State) ->
    {next_state, wait_for_capable, State}.

normal({timeout, T, tick}, #state{timer=T}=State) ->
    T1 = schedule_tick(),
    case is_capable() of
        false ->
            %% Not sure how, but we transitioned back to incompatible.
            %% Remove any internal state and transition back to
            %% incapable.
            {next_state, wait_for_capable, State#state{
                                             config=undefined,
                                             members=undefined,
                                             timer=T1}};
        true ->
            %% Get the latest config and see if it matches, merging
            %% with local state for safety.
            Config0 = State#state.config,
            PeerConfig = ?MAP:merge(Config0, get_raw_config()),
            PeersChanged = ?MAP:equal(Config0, PeerConfig),

            %% Compute any membership differences and remove them
            OldMembers = State#state.members,
            NewMembers = get_members(),
            RemovedMembers = ordsets:to_list(ordsets:subtract(OldMembers, NewMembers)),
            Config1 = remove_members(State#state.actor, PeerConfig, RemovedMembers),
            DidRemove = (RemovedMembers == []),

            %% Store the updated config and broadcast if it changed
            ShouldUpdate = PeersChanged orelse DidRemove,
            maybe_store(ShouldUpdate, Config1),
            maybe_notify(ShouldUpdate, Config1),
            {next_state, normal, State#state{config=Config1,
                                             members=NewMembers,
                                             timer=T1}}
    end.

normal(_Event, _From, State) ->
    {next_state, normal, State}.

handle_event(_Event, StateName, State) ->
    {next_state, StateName, State}.


handle_sync_event(get_config, _From, StateName, #state{config=undefined}=State) ->
    {reply, {error, invalid}, StateName, State};
handle_sync_event(get_config, _From, StateName, #state{config=Config}=State) ->
    {reply, {ok, value(Config)}, StateName, State};
handle_sync_event(_Event, _From, StateName, State) ->
    {reply, ignored, StateName, State}.

handle_info(_Msg, StateName, State) ->
    {next_state, StateName, State}.

terminate(_Reason, _StateName, _State) ->
    ok.

code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

%%---------------------------
%% Private functions
%%---------------------------
get_raw_config() ->
    riak_core_metadata:get(riak_api, peer_info,
                           [{default, ?MAP:new()},
                            {resolver, fun ?MAP:merge/2}]).

value(Map) ->
    [ {K, V} || {{K, _}, V} <- ?MAP:value(Map) ].

remove_members(_AID, Config, []) -> Config;
remove_members(AID, Config, Removals) ->
    Ops = [ {remove, ?PEER_KEY(Node)} || Node <- Removals ],
    ?MAP:update({update, Ops}, AID, Config).

update_my_config(State) ->
    OldConfig = get_raw_config(),
    update_my_config(OldConfig, State).

update_my_config(OldConfig, #state{actor=AID}) ->
    Data = lists:sort([{interfaces, riak_api_config:get_interfaces()} |riak_api_config:get_listeners()]),
    ?MAP:update({update, [{update, ?LOCAL_KEY, [{assign, Data, make_micro_epoch()}]}]},
                            AID, OldConfig).

maybe_store(true, NewConfig) -> store_config(NewConfig);
maybe_store(_, Config) -> Config.

maybe_notify(_Bool, _Config) -> todo.

store_config(NewConfig) ->
    riak_core_metadata:put(riak_api, peer_info, NewConfig),
    NewConfig.

is_capable() ->
    riak_core_capability:get({riak_api, discovery}, false).

get_members() ->
    {ok, Ring} = riak_core_ring_manager:get_my_ring(),
    get_members(Ring).

get_members(Ring) ->
    %% For now we choose only 'ready' members with the expectation
    %% that it is a bad thing to start hammering nodes that are
    %% joining or exiting.
    ordsets:from_list(riak_core_ring:ready_members(Ring)).

schedule_tick() ->
    %% We use the capability timer from riak_core
    Tick = app_helper:get_env(riak_core,
                              capability_tick,
                              10000),
    schedule_tick(Tick).

schedule_tick(Time) ->
    gen_fsm:start_timer(Time, tick).

make_micro_epoch() ->
    %% TODO: export this from lwwreg
    {Mega, Sec, Micro} = os:timestamp(),
    (Mega * 1000000 + Sec) * 1000000 + Micro.
