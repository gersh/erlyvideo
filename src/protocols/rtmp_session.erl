%%%---------------------------------------------------------------------------------------
%%% @author     Max Lapshin <max@maxidoors.ru> [http://erlyvideo.org]
%%% @copyright  2009 Max Lapshin
%%% @doc        RTMP session
%%% @reference  See <a href="http://erlyvideo.org" target="_top">http://erlyvideo.org</a> for more information
%%% @end
%%%
%%%
%%% The MIT License
%%%
%%% Copyright (c) 2007 Luke Hubbard, Stuart Jackson, Roberto Saccon, 2009 Max Lapshin
%%%
%%% Permission is hereby granted, free of charge, to any person obtaining a copy
%%% of this software and associated documentation files (the "Software"), to deal
%%% in the Software without restriction, including without limitation the rights
%%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%%% copies of the Software, and to permit persons to whom the Software is
%%% furnished to do so, subject to the following conditions:
%%%
%%% The above copyright notice and this permission notice shall be included in
%%% all copies or substantial portions of the Software.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%%% THE SOFTWARE.
%%%
%%%---------------------------------------------------------------------------------------
-module(rtmp_session).
-author('Max Lapshin <max@maxidoors.ru>').
-include_lib("erlmedia/include/video_frame.hrl").
-include("../../include/ems.hrl").
-include("../../include/rtmp_session.hrl").

-behaviour(gen_fsm).

-export([start_link/0, set_socket/2]).

%% gen_fsm callbacks
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).

-export([send/2]).

%% FSM States
-export([
  'WAIT_FOR_SOCKET'/2,
  'WAIT_FOR_HANDSHAKE'/2,
  'WAIT_FOR_DATA'/2,
  'WAIT_FOR_DATA'/3]).


-export([create_client/1]).
-export([accept_connection/1, reject_connection/1]).
-export([message/4]).

-export([reply/2, fail/2]).

%%-------------------------------------------------------------------------
%% @spec create_client(Socket)  -> {ok, Pid}
%% @doc Very important function. rtmp_listener calls it to
%% create new process, that will accept socket.
%% @end
%%-------------------------------------------------------------------------
create_client(Socket) ->
  {ok, Pid} = ems_sup:start_rtmp_session(Socket),
  {ok, Pid}.


accept_connection(#rtmp_session{host = Host, socket = Socket, amf_ver = AMFVersion} = Session) ->
  Message = #rtmp_message{channel_id = 2, timestamp = 0, body = <<>>},
  % gen_fsm:send_event(self(), {invoke, AMF#rtmp_funcall{command = 'onBWDone', type = invoke, id = 2, stream_id = 0, args = [null]}}),
  rtmp_socket:send(Socket, Message#rtmp_message{type = window_size, body = ?RTMP_WINDOW_SIZE}),
  rtmp_socket:send(Socket, Message#rtmp_message{type = bw_peer, body = ?RTMP_WINDOW_SIZE}),
  rtmp_socket:send(Socket, Message#rtmp_message{type = stream_begin, stream_id = 0}),
  % rtmp_socket:send(Socket, Message#rtmp_message{type = stream_begin}),
  rtmp_socket:setopts(Socket, [{chunk_size, ?RTMP_PREF_CHUNK_SIZE}]),
  
  ConnectObj = [{fmsVer, <<"FMS/3,5,2,654">>}, {capabilities, 31}, {mode, 1}],
  StatusObj = [{level, <<"status">>}, 
               {code, <<"NetConnection.Connect.Success">>},
               {description, <<"Connection succeeded.">>},
               {data,[<<"version">>, <<"3,5,2,654">>]},
               {objectEncoding, AMFVersion}],
  reply(Socket, #rtmp_funcall{id = 1, args = [{object, ConnectObj}, {object, StatusObj}]}),
  rtmp_socket:setopts(Socket, [{amf_version, AMFVersion}]),
  ems_event:user_connected(Host, self()),
  Session;
  
accept_connection(Session) when is_pid(Session) ->
  gen_fsm:send_event(Session, accept_connection).


reject_connection(#rtmp_session{socket = Socket} = Session) ->
  ConnectObj = [{fmsVer, <<"FMS/3,5,2,654">>}, {capabilities, 31}, {mode, 1}],
  StatusObj = [{level, <<"status">>}, 
               {code, <<?NC_CONNECT_REJECTED>>},
               {description, <<"Connection rejected.">>}],
  reply(Socket, #rtmp_funcall{id = 1, args = [{object, ConnectObj}, {object, StatusObj}]}),
  gen_fsm:send_event(self(), exit),
  Session;
  
reject_connection(Session) when is_pid(Session) ->
  gen_fsm:send_event(Session, reject_connection).

  
  
reply(#rtmp_session{socket = Socket}, AMF) ->
  rtmp_socket:invoke(Socket, AMF#rtmp_funcall{command = '_result', type = invoke});
reply(Socket, AMF) when is_pid(Socket) ->
  rtmp_socket:invoke(Socket, AMF#rtmp_funcall{command = '_result', type = invoke}).


fail(#rtmp_session{socket = Socket}, AMF) ->
  rtmp_socket:invoke(Socket, AMF#rtmp_funcall{command = '_error', type = invoke}).


message(Pid, Stream, Code, Body) ->
  gen_fsm:send_event(Pid, {message, Stream, Code, Body}).

  
%%%------------------------------------------------------------------------
%%% API
%%%------------------------------------------------------------------------

start_link() ->
  gen_fsm:start_link(?MODULE, [], []).

set_socket(Pid, Socket) when is_pid(Pid) ->
  gen_fsm:send_event(Pid, {socket_ready, Socket}).

%%%------------------------------------------------------------------------
%%% Callback functions from gen_server
%%%------------------------------------------------------------------------

%%-------------------------------------------------------------------------
%% Func: init/1
%% Returns: {ok, StateName, StateData}          |
%%          {ok, StateName, StateData, Timeout} |
%%          ignore                              |
%%          {stop, StopReason}
%% @private
%%-------------------------------------------------------------------------
init([]) ->
  random:seed(now()),
  {ok, 'WAIT_FOR_SOCKET', #rtmp_session{}}.


send(Session, Message) ->
  % case process_info(Session, message_queue_len) of
  %   {message_queue_len, Length} when Length > 100 ->
  %     % ?D({"Session is too slow in consuming messages", Session, Length}),
  %     ok;
  %   _ -> ok
  % end,
  Session ! Message.
  


%%-------------------------------------------------------------------------
%% Func: StateName/2
%% Returns: {next_state, NextStateName, NextStateData}          |
%%          {next_state, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}
%% @private
%%-------------------------------------------------------------------------
'WAIT_FOR_SOCKET'({socket_ready, RTMP}, State) when is_pid(RTMP) ->
  {address, {IP, Port}} = rtmp_socket:getopts(RTMP, address),
  Addr = case IP of
    undefined -> "0.0.0.0";
    _ -> lists:flatten(io_lib:format("~p.~p.~p.~p", erlang:tuple_to_list(IP)))
  end,
  erlang:monitor(process, RTMP),
  {next_state, 'WAIT_FOR_HANDSHAKE', State#rtmp_session{socket = RTMP, addr = Addr, port = Port}};


    
'WAIT_FOR_SOCKET'(Other, State) ->
  error_logger:error_msg("State: 'WAIT_FOR_SOCKET'. Unexpected message: ~p\n", [Other]),
  {next_state, 'WAIT_FOR_SOCKET', State}.

'WAIT_FOR_HANDSHAKE'(timeout, #rtmp_session{host = Host, user_id = UserId, addr = IP} = State) ->
  ems_log:error(Host, "TIMEOUT ~p ~p", [UserId, IP]),
  {stop, normal, State}.

%% Notification event coming from client

'WAIT_FOR_DATA'(exit, State) ->
  {stop, normal, State};

'WAIT_FOR_DATA'(#rtmp_message{} = Message, State) ->
  rtmp_socket:send(State#rtmp_session.socket, Message),
  {next_state, 'WAIT_FOR_DATA', State};

'WAIT_FOR_DATA'(accept_connection, Session) ->
  {next_state, 'WAIT_FOR_DATA', accept_connection(Session)};

'WAIT_FOR_DATA'(reject_connection, Session) ->
  reject_connection(Session),
  {stop, normal, Session};

'WAIT_FOR_DATA'({message, Stream, Code, Body}, #rtmp_session{socket = Socket} = State) ->
  rtmp_socket:status(Socket, Stream, Code, Body),
  {next_state, 'WAIT_FOR_DATA', State};

'WAIT_FOR_DATA'(Message, #rtmp_session{host = Host} = State) ->
  case ems:try_method_chain(Host, 'WAIT_FOR_DATA', [Message, State]) of
    {unhandled} ->
		  ?D({"Ignoring message:", Message}),
      {next_state, 'WAIT_FOR_DATA', State};
    Reply -> Reply
  end.

%% Sync event

'WAIT_FOR_DATA'(info, _From, #rtmp_session{addr = {IP1, IP2, IP3, IP4}, port = Port} = State) ->
  {reply, {io_lib:format("~p.~p.~p.~p", [IP1, IP2, IP3, IP4]), Port, self()}, 'WAIT_FOR_DATA', State};

  
'WAIT_FOR_DATA'(Data, _From, State) ->
	io:format("~p Ignoring data: ~p\n", [self(), Data]),
  {next_state, 'WAIT_FOR_DATA', State}.
    
    
% send(#rtmp_session{server_chunk_size = ChunkSize} = State, {#channel{} = Channel, Data}) ->
%   Packet = rtmp:encode(Channel#channel{chunk_size = ChunkSize}, Data),
%   % ?D({"Channel", Channel#channel.type, Channel#channel.timestamp, Channel#channel.length}),
%   send_data(State, Packet).
	

handle_rtmp_message(State, #rtmp_message{type = invoke, body = AMF}) ->
  #rtmp_funcall{command = CommandBin} = AMF,
  Command = binary_to_atom(CommandBin, utf8),
  call_function(ems:check_app(State#rtmp_session.host, Command, 2), State, AMF#rtmp_funcall{command = Command});
  
handle_rtmp_message(#rtmp_session{streams = Streams} = State, 
   #rtmp_message{type = Type, stream_id = StreamId, body = Body, timestamp = Timestamp}) when (Type == video) or (Type == audio) or (Type == metadata) or (Type == metadata3) ->
  Recorder = ems:element(StreamId, Streams),
  
  catch begin Frame = flv_video_frame:decode(#video_frame{dts = Timestamp, pts = Timestamp, content = Type}, Body),
  ems_media:publish(Recorder, Frame)
  end,	
  State;

handle_rtmp_message(State, #rtmp_message{type = shared_object, body = SOEvent}) ->
  #so_message{name = Name, persistent = Persistent} = SOEvent,
  ?D({"Shared object", Name}),
  {NewState, Object} = find_shared_object(State, Name, Persistent),
  shared_object:message(Object, SOEvent),
  NewState;

handle_rtmp_message(#rtmp_session{streams = Streams} = State, #rtmp_message{stream_id = StreamId, type = buffer_size, body = BufferSize}) ->
  case ems:element(StreamId, Streams) of
    Player when is_pid(Player) -> ems_media:setopts(Player, [{client_buffer, BufferSize}]);
    _ -> ok
  end,
  State;

handle_rtmp_message(State, #rtmp_message{type = pong}) -> State;
handle_rtmp_message(State, #rtmp_message{type = ping}) -> State;
handle_rtmp_message(State, #rtmp_message{type = ack_read}) -> State;
handle_rtmp_message(State, #rtmp_message{type = window_size}) -> State;
handle_rtmp_message(State, #rtmp_message{type = chunk_size}) -> State;
handle_rtmp_message(State, #rtmp_message{type = broken_meta}) -> State;

handle_rtmp_message(State, Message) ->
  ?D({"RTMP", Message#rtmp_message.type}),
  State.


find_shared_object(#rtmp_session{host = Host, cached_shared_objects = Objects} = State, Name, Persistent) ->
  case lists:keysearch(Name, 1, Objects) of
    false ->
      Object = shared_objects:open(Host, Name, Persistent),
      NewObjects = lists:keystore(Name, 1, Objects, {Name, Object}),
      {State#rtmp_session{cached_shared_objects = NewObjects}, Object};
    {value, {Name, Object}} ->
      {State, Object}
  end.

call_function(unhandled, #rtmp_session{host = Host, addr = IP} = State, #rtmp_funcall{command = Command, args = Args}) ->
  ems_log:error(Host, "Client ~p requested unknown function ~p(~p)~n", [IP, Command, Args]),
  State;

call_function(_, #rtmp_session{} = State, #rtmp_funcall{command = connect, args = [{object, PlayerInfo} | _]} = AMF) ->
  URL = proplists:get_value(tcUrl, PlayerInfo),
  {ok, UrlRe} = re:compile("(.*)://([^/]+)/?(.*)$"),
  {match, [_, _Proto, HostName, Path]} = re:run(URL, UrlRe, [{capture, all, binary}]),
  Host = ems:host(HostName),
  
  ?D({"Client connected", HostName, Host, AMF#rtmp_funcall.args}),

  AMFVersion = case lists:keyfind(objectEncoding, 1, PlayerInfo) of
    {objectEncoding, 0.0} -> 0;
    {objectEncoding, 3.0} -> 3;
    {objectEncoding, _N} -> 
      error_logger:error_msg("Warning! Cannot work with clients, using not AMF0/AMF3 encoding.
      Assume _connection.objectEncoding = ObjectEncoding.AMF0; in your flash code is used version ~p~n", [_N]),
      throw(invalid_amf3_encoding);
    _ -> 0
  end,
  

	NewState1 =	State#rtmp_session{player_info = PlayerInfo, host = Host, path = Path, amf_ver = AMFVersion},

  {Module, Function} = ems:check_app(NewState1#rtmp_session.host, connect, 2),

	Module:Function(NewState1, AMF);

call_function({Module, Function}, State, AMF) ->
	Module:Function(State, AMF).
  % try
  %   App:Command(AMF, State)
  % catch
  %   _:login_failed ->
  %     throw(login_failed);
  %   What:Error ->
  %     error_logger:error_msg("Command failed: ~p:~p(~p, ~p):~n~p:~p~n~p~n", [App, Command, AMF, State, What, Error, erlang:get_stacktrace()]),
  %     % apps_rtmp:fail(Id, [null, lists:flatten(io_lib:format("~p", [Error]))]),
  %     State
  % end.

	
%%-------------------------------------------------------------------------
%% Func: handle_event/3
%% Returns: {next_state, NextStateName, NextStateData}          |
%%          {next_state, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}
%% @private
%%-------------------------------------------------------------------------
handle_event(Event, StateName, StateData) ->
  {stop, {StateName, undefined_event, Event}, StateData}.


%%-------------------------------------------------------------------------
%% Func: handle_sync_event/4
%% Returns: {next_state, NextStateName, NextStateData}            |
%%          {next_state, NextStateName, NextStateData, Timeout}   |
%%          {reply, Reply, NextStateName, NextStateData}          |
%%          {reply, Reply, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}                          |
%%          {stop, Reason, Reply, NewStateData}
%% @private
%%-------------------------------------------------------------------------

handle_sync_event(Event, _From, StateName, StateData) ->
  io:format("TRACE ~p:~p ~p~n",[?MODULE, ?LINE, got_sync_request2]),
  {stop, {StateName, undefined_event, Event}, StateData}.

%%-------------------------------------------------------------------------
%% Func: handle_info/3
%% Returns: {next_state, NextStateName, NextStateData}          |
%%          {next_state, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}
%% @private
%%-------------------------------------------------------------------------
handle_info({rtmp, _Socket, disconnect, Stats}, _StateName, #rtmp_session{} = StateData) ->
  BytesSent = proplists:get_value(send_oct, Stats, 0),
  BytesRecv = proplists:get_value(recv_oct, Stats, 0),
  {stop, normal, StateData#rtmp_session{bytes_sent = BytesSent, bytes_recv = BytesRecv}};

handle_info({rtmp, Socket, #rtmp_message{} = Message}, StateName, State) ->
  State1 = handle_rtmp_message(State, Message),
  State2 = flush_reply(State1),
  % [{message_queue_len, Messages}, {memory, Memory}] = process_info(self(), [message_queue_len, memory]),
  % io:format("messages=~p,memory=~p~n", [Messages, Memory]),
  rtmp_socket:setopts(Socket, [{active, once}]),
  {next_state, StateName, State2};
  
handle_info({rtmp, Socket, connected}, 'WAIT_FOR_HANDSHAKE', State) ->
  rtmp_socket:setopts(Socket, [{active, once}]),
  {next_state, 'WAIT_FOR_DATA', State};

handle_info({rtmp, _Socket, timeout}, _StateName, #rtmp_session{host = Host, user_id = UserId, addr = IP} = State) ->
  ems_log:error(Host, "TIMEOUT ~p ~p ~p", [_Socket, UserId, IP]),
  {stop, normal, State};

handle_info({'DOWN', _Ref, process, Socket, _Reason}, _StateName, #rtmp_session{socket = Socket} = State) ->
  {stop,normal,State};
  
handle_info({'DOWN', _Ref, process, PlayerPid, _Reason}, StateName, #rtmp_session{socket = Socket, streams = Streams} = State) ->
  case ems:tuple_find(PlayerPid, Streams) of
    false -> 
      ?D({"Unknown linked pid failed", PlayerPid, _Reason}),
      {next_state, StateName, State};
    {StreamId, PlayerPid} ->
      rtmp_lib:play_complete(Socket, StreamId, []),
      NewStreams = setelement(StreamId, Streams, undefined),
      {next_state, StateName, State#rtmp_session{streams = NewStreams}}
  end;

handle_info({Port, {data, _Line}}, StateName, State) when is_port(Port) ->
  % No-op. Just child program
  {next_state, StateName, State};

handle_info({ems_stream, StreamId, start_play}, StateName, #rtmp_session{socket = Socket} = State) ->
  Player = element(StreamId, State#rtmp_session.streams),
  F = fun(Pid) ->
    S = pid_to_list(Pid),
    {ok, Re} = re:compile("<(\\d+)\\.(\\d+)\\.(\\d+)"),
    {match, [_, A, B, C]} = re:run(S, Re, [{capture, all, list}]),
    "pid("++A++","++B++","++C++")"
  end,  
  PidList = lists:map(F, [Socket, self(), Player]),
  io:format("eprof:start_profiling([~s,~s,~s]).~n", PidList),
  rtmp_lib:play_start(Socket, StreamId),
  {next_state, StateName, State};

handle_info({ems_stream, StreamId, {notfound, _Reason}}, StateName, #rtmp_session{socket = Socket} = State) ->
  rtmp_socket:status(Socket, StreamId, ?NS_PLAY_STREAM_NOT_FOUND),
  {next_state, StateName, State};
  
handle_info({ems_stream, _StreamId, play_stats, PlayStat}, StateName, #rtmp_session{play_stats = Stats} = State) ->
  ?D({"Play", PlayStat}),
  {next_state, StateName, State#rtmp_session{play_stats = [PlayStat | Stats]}};

handle_info({ems_stream, StreamId, play_complete, LastDTS}, StateName, #rtmp_session{socket = Socket} = State) ->
  rtmp_lib:play_complete(Socket, StreamId, [{duration, LastDTS}]),
  {next_state, StateName, State};

handle_info({ems_stream, StreamId, play_failed}, StateName, #rtmp_session{socket = Socket} = State) ->
  rtmp_lib:play_failed(Socket, StreamId),
  {next_state, StateName, State};
  

handle_info(#video_frame{} = Frame, 'WAIT_FOR_DATA', #rtmp_session{} = State) ->
  {next_state, 'WAIT_FOR_DATA', handle_frame(Frame, State)};

handle_info(#rtmp_message{} = Message, StateName, State) ->
  rtmp_socket:send(State#rtmp_session.socket, Message),
  {next_state, StateName, State};

handle_info(_Info, StateName, StateData) ->
  ?D({"Some info handled", _Info, StateName, StateData}),
  {next_state, StateName, StateData}.


handle_frame(#video_frame{content = Type, stream_id = StreamId, dts = DTS, pts = PTS} = Frame, 
             #rtmp_session{socket = Socket, streams_dts = StreamsDTS, streams_started = Started} = State) ->
  {State1, BaseDts, Starting} = case ems:element(StreamId, Started) of
    undefined ->
      rtmp_lib:play_start(Socket, StreamId, 0),
      {State#rtmp_session{
        streams_started = ems:setelement(StreamId, Started, true),
        streams_dts = ems:setelement(StreamId, StreamsDTS, DTS)}, DTS, true};
    _ ->
      {State, ems:element(StreamId, StreamsDTS), false}
  end,
    
  % ?D({Type,Frame#video_frame.flavor,round(DTS), round(PTS), BaseDts}),
  Message = #rtmp_message{
    channel_id = rtmp_lib:channel_id(Type, StreamId), 
    timestamp = DTS - BaseDts,
    type = Type,
    stream_id = StreamId,
    body = flv_video_frame:encode(Frame#video_frame{dts = DTS - BaseDts, pts = PTS - BaseDts})},
	rtmp_socket:send(Socket, Message),
	case {Starting, Frame} of
	  {true, #video_frame{content = video, flavor = config}} -> rtmp_socket:send(Socket, Message);
	  _ -> ok
	end,
  State1.

flush_reply(#rtmp_session{socket = Socket} = State) ->
  receive
    #rtmp_message{} = Message ->
      rtmp_socket:send(Socket, Message),
      flush_reply(State)
    after
      0 -> State
  end.


collect_statistics(#rtmp_session{socket = Socket}) ->
  Stats = rtmp_socket:getstat(Socket),
  Stats.

%%-------------------------------------------------------------------------
%% Func: terminate/3
%% Purpose: Shutdown the fsm
%% Returns: any
%% @private
%%-------------------------------------------------------------------------
terminate(_Reason, _StateName, #rtmp_session{socket=Socket,
  addr = Addr, bytes_recv = Recv, bytes_sent = Sent, play_stats = PlayStats, user_id = UserId} = State) ->
  erlyvideo:call_modules(logout, [State]),
  (catch rtmp_listener:logout()),
  (catch gen_tcp:close(Socket)),
  ems_event:user_disconnected(State#rtmp_session.host, [{recv_oct,Recv},{sent_oct,Sent},{addr,Addr},{user_id,UserId}|PlayStats]),
  ok.


%%-------------------------------------------------------------------------
%% Func: code_change/4
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState, NewStateData}
%% @private
%%-------------------------------------------------------------------------
code_change(OldVersion, StateName, #rtmp_session{host = Host} = State, Extra) ->
  plugins_code_change(OldVersion, StateName, State, Extra, ems:get_var(applications, Host, [])).

plugins_code_change(_OldVersion, StateName, State, _Extra, []) -> {ok, StateName, State};

plugins_code_change(OldVersion, StateName, State, Extra, [Module | Modules]) -> 
  case ems:respond_to(Module, code_change, 4) of
    true ->
      error_logger:info_msg("Code change in module ~p~n", [Module]),
      {ok, NewStateName, NewState} = Module:code_change(OldVersion, StateName, State, Extra);
    _ ->
      {NewStateName, NewState} = {StateName, State}
  end,
  plugins_code_change(OldVersion, NewStateName, NewState, Extra, Modules).




