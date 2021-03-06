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
-module(rtsp_media).
-author('Max Lapshin <max@maxidoors.ru>').
-behaviour(ems_media).
-include("../../include/ems_media.hrl").
-include("../../include/ems.hrl").

-export([init/2, handle_frame/2, handle_control/2, handle_info/2]).

-record(rtsp, {
  timeout,
  reader,
  restart_count = 0
}).

connect_rtsp(#ems_media{url = URL, state = #rtsp{timeout = Timeout}}) ->
  ?D({"Connecting to RTSP", URL}),
  rtsp_socket:read(URL, [{consumer, self()},{interleaved,true},{timeout,Timeout}]).



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
  Timeout = proplists:get_value(timeout, Options, 5000),
  State = #rtsp{timeout = Timeout},
  self() ! make_request,
  {ok, Media#ems_media{state = State, source_timeout = live_media:default_timeout(), clients_timeout = live_media:default_timeout()}}.

%%----------------------------------------------------------------------
%% @spec (ControlInfo::tuple(), State) -> {reply, Reply, State} |
%%                                        {stop, Reason, State} |
%%                                        {error, Reason}
%%
%% @doc Called by ems_media to handle specific events
%% @end
%%----------------------------------------------------------------------
handle_control({subscribe, _Client, _Options}, State) ->
  {noreply, State};

handle_control({source_lost, _Source}, #ems_media{} = Media) ->
  %% Source lost returns:
  %% {ok, State, Source} -> new source is created
  %% {stop, Reason, State} -> stop with Reason
  self() ! make_request,
  {noreply, Media};

handle_control({set_source, _Source}, State) ->
  %% Set source returns:
  %% {reply, Reply, State}
  %% {stop, Reason}
  {noreply, State};

handle_control(no_clients, State) ->
  %% no_clients returns:
  %% {reply, ok, State}      => wait forever till clients returns
  %% {reply, Timeout, State} => wait for Timeout till clients returns
  %% {noreply, State}        => just ignore and live more
  %% {stop, Reason, State}   => stops. This should be default
  {noreply, State};

handle_control(timeout, #ems_media{source = Reader} = Media) ->
  erlang:exit(Reader, shutdown),
  ?D("RTSP timeout"),
  {noreply, Media};

handle_control(_Control, State) ->
  {noreply, State}.

%%----------------------------------------------------------------------
%% @spec (Frame::video_frame(), State) -> {ok, Frame, State} |
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
handle_info(make_request, #ems_media{retry_count = Count, retry_limit = Limit} = Media) when 
  (is_number(Count) andalso is_number(Limit) andalso Count =< Limit) orelse Limit == false ->
  case connect_rtsp(Media) of
    {ok, Reader} ->
      ems_media:set_source(self(), Reader),
      {noreply, Media#ems_media{retry_count = 0}};
    _Else ->
      ?D({"Failed to open rtsp_source", Media#ems_media.url, "retry count/limit", Count, Limit}),
      timer:send_after(1000, make_request),
      {noreply, Media#ems_media{retry_count = Count + 1}}
  end;

handle_info(make_request, Media) ->
  ?D("No RTSP source and retry limits are over"),
  {stop, normal, Media};
  
handle_info(_Message, State) ->
  {noreply, State}.








