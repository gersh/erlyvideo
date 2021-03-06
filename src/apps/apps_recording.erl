%%%---------------------------------------------------------------------------------------
%%% @author     Max Lapshin <max@maxidoors.ru> [http://erlyvideo.org]
%%% @copyright  2009 Max Lapshin
%%% @doc        RTMP functions, that support recording
%%% @reference  See <a href="http://erlyvideo.org/" target="_top">http://erlyvideo.org</a> for more information
%%% @end
%%%
%%%
%%% The MIT License
%%%
%%% Copyright (c) 2009 Max Lapshin
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
-module(apps_recording).
-author('Max Lapshin <max@maxidoors.ru>').
-include("../../include/ems.hrl").
-include("../../include/rtmp_session.hrl").
-include_lib("erlmedia/include/video_frame.hrl").

-export([publish/2]).
-export(['FCPublish'/2, 'FCUnpublish'/2]).


%%-------------------------------------------------------------------------
%% @private
%%-------------------------------------------------------------------------

'FCPublish'(State, #rtmp_funcall{args = [null, Name]} = _AMF) -> 
  ?D({"FCpublish", Name}),
  State.

'FCUnpublish'(State, #rtmp_funcall{args = Args} = AMF) ->
  ?D({"FCunpublish", Args}),
  apps_streaming:stop(State, AMF).
  % rtmp_session:reply(State,AMF#rtmp_funcall{args = [null, undefined]}),
  % State.

publish(#rtmp_session{host = Host, streams = Streams} = State, #rtmp_funcall{args = [null,Name, <<"record">>], stream_id = StreamId} = _AMF) -> 
  ?D({"Publish - Action - record",Name}),
  {ok, Recorder} = media_provider:create(Host, Name, [{type, record}]),
  State#rtmp_session{streams = ems:setelement(StreamId, Streams, Recorder)};


publish(State, #rtmp_funcall{args = [null,Name,<<"append">>]} = _AMF) -> 
  ?D({"Publish - Action - append",Name}),
  gen_fsm:send_event(self(), {publish, append, Name}),
  State;


publish(State, #rtmp_funcall{args = [null,URL,<<"LIVE">>]} = AMF) ->
  ?D({"publish LIVE rewriting to live", URL}),
  publish(State, AMF#rtmp_funcall{args = [null,URL,<<"live">>]});

publish(#rtmp_session{host = Host, streams = Streams, socket = Socket} = State, #rtmp_funcall{args = [null,URL,<<"live">>], stream_id = StreamId} = _AMF) -> 
  [Name | _Params] = string:tokens(binary_to_list(URL), "?"),
  ?D({"LIVE", _AMF#rtmp_funcall.stream_id}),
  ems_log:access(Host, "RECORD LIVE ~s ~p ~s", [State#rtmp_session.addr, State#rtmp_session.user_id, Name]),
  {ok, Recorder} = media_provider:create(Host, Name, [{type, live}]),
  rtmp_socket:send(Socket, #rtmp_message{type = stream_begin, stream_id = StreamId}),
  rtmp_socket:status(Socket, StreamId, ?NS_PUBLISH_START),
  State#rtmp_session{streams = ems:setelement(StreamId, Streams, Recorder)};

publish(State, #rtmp_funcall{args = [null, false]} = AMF) ->
  apps_streaming:stop(State, AMF);

publish(State, #rtmp_funcall{args = [null, null]} = AMF) ->
  apps_streaming:stop(State, AMF);

publish(State, #rtmp_funcall{args = [null, <<"null">>]} = AMF) ->
  apps_streaming:stop(State, AMF);
  
publish(#rtmp_session{host = Host, streams = Streams} = State, #rtmp_funcall{args = [null,Name], stream_id = StreamId} = _AMF) -> 
  ems_log:access(Host, "LIVE ~s ~p ~s", [State#rtmp_session.addr, State#rtmp_session.user_id, Name]),
  {ok, Recorder} = media_provider:create(Host, Name, [{type, live}]),
  State#rtmp_session{streams = ems:setelement(StreamId, Streams, Recorder)}.

