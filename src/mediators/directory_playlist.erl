%%% @author     Max Lapshin <max@maxidoors.ru>
%%% @copyright  2009 Max Lapshin
%%% @doc        ems_media handler template
%%% @reference  See <a href="http://erlyvideo.org/" target="_top">http://erlyvideo.org/</a> for more information
%%% @end
%%%
%%%
%%% The MIT License
%%%
%%% Copyright (c) 2010 Max Lapshin
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
-module(directory_playlist).
-author('Max Lapshin <max@maxidoors.ru>').
-behaviour(ems_media).
-include("../../include/ems_media.hrl").
-include("../../include/ems.hrl").


-export([init/2, handle_frame/2, handle_control/2, handle_info/2]).

-record(playlist, {
  path,
  host,
  files = []
}).

%%%------------------------------------------------------------------------
%%% Callback functions from ems_media
%%%------------------------------------------------------------------------

%%----------------------------------------------------------------------
%% @spec (Media::ems_media(), Options::list()) -> {ok, Media::ems_media()} |
%%                                                {stop, Reason}
%%
%% @doc Called by ems_media to initialize specific data for current media type
%% @end
%%----------------------------------------------------------------------

init(Media, Options) ->
  Path = proplists:get_value(path, Options),
  Host = proplists:get_value(host, Options),
  AbsPath = filename:join([file_media:file_dir(Host), Path]),
  Wildcard = proplists:get_value(wildcard, Options),
  Files = [filename:join(Path,File) || File <- filelib:wildcard(Wildcard, AbsPath)],
  ?D({AbsPath, Wildcard, Files}),
  
  self() ! start_playing,
  State = #playlist{path = AbsPath, files = Files, host = Host},
  {ok, Media#ems_media{state = State}}.

%%----------------------------------------------------------------------
%% @spec (ControlInfo::tuple(), State) -> {reply, Reply, State} |
%%                                        {stop, Reason, State} |
%%                                        {error, Reason}
%%
%% @doc Called by ems_media to handle specific events
%% @end
%%----------------------------------------------------------------------
handle_control({subscribe, _Client, _Options}, State) ->
  %% Subscribe returns:
  %% {reply, tick, State} -> client requires ticker (file reader)
  %% {reply, Reply, State} -> client is subscribed as active receiver
  %% {reply, {error, Reason}, State} -> client receives {error, Reason}
  {noreply, State};

handle_control({source_lost, _Source}, State) ->
  %% Source lost returns:
  %% {reply, Source, State} -> new source is created
  %% {stop, Reason, State} -> stop with Reason
  {Stream, State1} = next_file(State),
  {reply, Stream, State1};

handle_control({set_source, _Source}, State) ->
  %% Set source returns:
  %% {reply, Reply, State}
  %% {stop, Reason, State}
  {noreply, State};

handle_control({set_socket, _Socket}, State) ->
  %% Set socket returns:
  %% {reply, Reply, State}
  %% {stop, Reason, State}
  {noreply, State};

handle_control(timeout, State) ->
  {stop, timeout, State};

handle_control(_Control, State) ->
  {noreply, State}.

%%----------------------------------------------------------------------
%% @spec (Frame::video_frame(), State) -> {reply, Frame, State} |
%%                                        {noreply, State}   |
%%                                        {stop, Reason, State}
%%
%% @doc Called by ems_media to parse frame.
%% @end
%%----------------------------------------------------------------------
handle_frame(Frame, State) ->
  {reply, Frame, State}.


%%----------------------------------------------------------------------
%% @spec (Message::any(), State) ->  {noreply, State}   |
%%                                   {stop, Reason, State}
%%
%% @doc Called by ems_media to parse incoming message.
%% @end
%%----------------------------------------------------------------------
handle_info(start_playing, #ems_media{state = #playlist{host = Host, files = [Name|Files]}} = Media) ->
  State = Media#ems_media.state,
  {ok, Stream} = media_provider:play(Host, Name, [{stream_id,1}]),
  ?D({"Playing",Name, Stream}),
  {noreply, Media#ems_media{state = State#playlist{files = Files}}};

handle_info({ems_stream, _StreamId, play_complete, _DTS}, #ems_media{state = #playlist{host = Host, files = [Name|Files]}} = Media) ->
  State = Media#ems_media.state,
  {ok, Stream} = media_provider:play(Host, Name, [{stream_id,1}]),
  ems_media:set_source(self(), undefined),
  ?D({"Playing",Name,Stream}),
  {noreply, Media#ems_media{state = State#playlist{files = Files}}};

handle_info(timeout, State) ->
  {stop, normal, State};

handle_info(_Message, State) ->
  ?D({message, _Message}),
  {noreply, State}.

next_file(#ems_media{state = #playlist{host = Host, files = [Name|Files]}} = Media) ->
  State = Media#ems_media.state,
  {ok, Stream} = media_provider:play(Host, Name, [{stream_id,1}]),
  ems_media:set_source(self(), Stream),
  ?D({"Playing",Name, Stream}),
  {Stream, Media#ems_media{state = State#playlist{files = Files}}}.
  


