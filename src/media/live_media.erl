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
-module(live_media).
-author('Max Lapshin <max@maxidoors.ru>').
-behaviour(ems_media).
-include("../../include/ems_media.hrl").
-include("../../include/ems.hrl").

-export([init/2, handle_frame/2, handle_control/2, handle_info/2]).
-export([default_timeout/0]).

-record(live, {
  timeout,
  ref
}).

default_timeout() ->
  600000.

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
  State = case proplists:get_value(wait, Options, default_timeout()) of
    Timeout when is_number(Timeout) ->
      {ok, Ref} = timer:send_after(Timeout, source_timeout),
      #live{timeout = Timeout, ref = Ref};
    infinity ->
      #live{}
  end,
  Media1 = Media#ems_media{state = State, clients_timeout = false, source_timeout = default_timeout()},
  case proplists:get_value(type, Options) of
    live -> 
      {ok, Media1};
    undefined -> 
      {ok, Media1};
    record ->
      URL = proplists:get_value(url, Options),
      Host = proplists:get_value(host, Options),
    	FileName = filename:join([file_media:file_dir(Host), binary_to_list(URL)]),
    	(catch file:delete(FileName)),
    	ok = filelib:ensure_dir(FileName),
      {ok, Writer} = flv_writer:init(FileName),
      {ok, Media1#ems_media{format = flv_writer, storage = Writer}}
  end.

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
  {noreply, State};

handle_control({set_source, _Source}, #ems_media{state = #live{ref = undefined}} = State) ->
  {noreply, State};

handle_control({set_source, _Source}, #ems_media{state = State} = Media) ->
  #live{ref = Ref} = State,
  {ok, cancel} = timer:cancel(Ref),
  State1 = State#live{ref = undefined},
  {noreply, Media#ems_media{state = State1}};

handle_control(no_clients, #ems_media{source = undefined} = State) ->
  {stop, normal, State};

handle_control(no_clients, State) ->
  %% no_clients returns:
  %% {reply, ok, State}      => wait forever till clients returns
  %% {reply, Timeout, State} => wait for Timeout till clients returns
  %% {noreply, State}        => just ignore and live more
  %% {stop, Reason, State}   => stops. This should be default
  ?D({"No clients, but has source", State#ems_media.source}),
  {noreply, State};

handle_control(timeout, State) ->
  {noreply, State};

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
handle_info(source_timeout, State) ->
  {stop, timeout, State};

handle_info(_Message, State) ->
  {noreply, State}.


