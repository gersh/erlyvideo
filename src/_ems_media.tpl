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
-module(_ems_media_tpl).
-author('Max Lapshin <max@maxidoors.ru>').
-behaviour(ems_media).
-include_lib("erlyvideo/include/ems_media.hrl").
%-include("../include/ems_media.hrl").
-include("../include/ems.hrl").

-export([init/2, handle_frame/2, handle_control/2, handle_info/2]).

-record(state, {
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

init(State, Options) ->
  {ok, State}.

%%----------------------------------------------------------------------
%% @spec (ControlInfo::tuple(), State) -> {reply, Reply, State} |
%%                                        {stop, Reason, State} |
%%                                        {error, Reason}
%%
%% @doc Called by ems_media to handle specific events
%% @end
%%----------------------------------------------------------------------
handle_control({subscribe, _Client, _Options}, #ems_media{} = State) ->
  %% Subscribe returns:
  %% {reply, tick, State}  => client requires ticker (file reader)
  %% {reply, Reply, State} => client is subscribed as active receiver and receives custom reply
  %% {noreply, State}      => client is subscribed as active receiver and receives reply ``ok''
  %% {reply, {error, Reason}, State} => client receives {error, Reason}
  {noreply, State};

handle_control({unsubscribe, _Client}, #ems_media{} = State) ->
  %% Unsubscribe returns:
  %% {reply, Reply, State} => client is unsubscribed inside plugin, but not rejected from ets table
  %% {noreply, State}      => client is unsubscribed in usual way.
  %% {reply, {error, Reason}, State} => client receives {error, Reason} 
  {noreply, State};

handle_control({seek, _Client, _BeforeAfter, _DTS}, #ems_media{} = State) ->
  %% seek returns:
  %% {reply, {NewPos, NewDTS}, State} => media knows how to seek in storage
  %% {stop, Reason, State}  => stop with Reason
  %% {noreply, State}       => default action is to seek in storage.
  {noreply, State};

handle_control({source_lost, _Source}, #ems_media{} = State) ->
  %% Source lost returns:
  %% {reply, Source, State} => new source is created
  %% {stop, Reason, State}  => stop with Reason
  %% {noreply, State}       => default action. it is stop
  {stop, normal, State};

handle_control({set_source, _Source}, #ems_media{} = State) ->
  %% Set source returns:
  %% {reply, NewSource, State} => source is rewritten
  %% {noreply, State}          => just ignore setting new source
  %% {stop, Reason, State}     => stop after setting
  {noreply, State};

handle_control({set_socket, _Socket}, #ems_media{} = State) ->
  %% Set socket returns:
  %% {reply, Reply, State}  => the same as noreply
  %% {noreply, State}       => just ignore
  %% {stop, Reason, State}  => stops
  {noreply, State};

handle_control(no_clients, #ems_media{} = State) ->
  %% no_clients returns:
  %% {reply, ok, State}      => wait forever till clients returns
  %% {reply, Timeout, State} => wait for Timeout till clients returns
  %% {noreply, State}        => just ignore and live more
  %% {stop, Reason, State}   => stops. This should be default
  {stop, normal, State};

handle_control(timeout, #ems_media{} = State) ->
  {stop, normal, State};

handle_control(_Control, #ems_media{} = State) ->
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
handle_info(_Message, State) ->
  {noreply, State}.








