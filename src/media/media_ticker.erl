-module(media_ticker).
-include_lib("erlmedia/include/video_frame.hrl").
-include("../../include/ems.hrl").

-export([start_link/3, init/3, loop/1, handle_message/2]).
-export([start/1, pause/1, resume/1, seek/3, stop/1]).

-record(ticker, {
  media,
  consumer,
  stream_id,
  pos,
  dts,
  frame,
  client_buffer,
  timer_start,
  playing_from,
  playing_till
}).

start(Ticker) ->
  Ticker ! start.

seek(Ticker, Pos, DTS) ->
  Ticker ! {seek, Pos, DTS}.

stop(Ticker) ->
  Ticker ! stop.

pause(Ticker) ->
  Ticker ! pause.

resume(Ticker) ->
  Ticker ! resume.

start_link(Media, Consumer, Options) ->
  proc_lib:start_link(?MODULE, init, [Media, Consumer, Options]).
  
init(Media, Consumer, Options) ->
  erlang:monitor(process, Media),
  erlang:monitor(process, Consumer),
  proc_lib:init_ack({ok, self()}),
  % ?D({media_ticker,Options}),
  StreamId = proplists:get_value(stream_id, Options),
  ClientBuffer = proplists:get_value(client_buffer, Options, 10000),
  {Pos, DTS} = case proplists:get_value(start, Options) of
    undefined -> {undefined, undefined};
    {BeforeAfter, Start} -> ems_media:seek_info(Media, BeforeAfter, Start);
    Start -> ems_media:seek_info(Media, before, Start)
  end,
  
  PlayingTill = case proplists:get_value(duration, Options) of
    undefined -> undefined;
    {BeforeAfterEnd, Duration} ->
      Length = proplists:get_value(length, media_provider:info(Media)),
      TotalDuration = case DTS of 
        undefined -> Duration;
        _ -> DTS + Duration
      end,
      if
        TotalDuration > Length -> TotalDuration;
        % TotalDuration + 1000 > Length -> undefined;
        true ->
          case ems_media:seek_info(Media, BeforeAfterEnd, TotalDuration) of
            {_Pos, EndTimestamp} -> EndTimestamp;
            _ -> undefined
          end
      end
  end,
  % ?D({media_ticker,{Pos,DTS}, PlayingTill, ClientBuffer}),
  ?MODULE:loop(#ticker{media = Media, consumer = Consumer, stream_id = StreamId, client_buffer = ClientBuffer,
                       pos = Pos, dts = DTS, playing_till = PlayingTill}).
  
loop(Ticker) ->
  receive
    Message ->
      ?MODULE:handle_message(Message, Ticker)
  end.


flush_tick() ->
  receive
    tick -> flush_tick()
  after 
    0 -> ok
  end.

notify_about_stop(#ticker{media = Media, dts = DTS, pos = Pos}) ->
  Media ! {ticker_stop, self(), DTS, Pos}.
  

handle_message({'DOWN', _Ref, process, _Pid, _Reason}, Ticker) ->
  notify_about_stop(Ticker),
  ok;

handle_message(stop, Ticker) ->
  notify_about_stop(Ticker),
  ok;

handle_message(start, Ticker) ->
  self() ! tick,
  ?MODULE:loop(Ticker);
  
handle_message(pause, Ticker) ->
  flush_tick(),
  ?MODULE:loop(Ticker);
  
handle_message({seek, Pos, DTS}, #ticker{} = Ticker) ->
  self() ! tick,
  ?MODULE:loop(Ticker#ticker{pos = Pos, dts = DTS, frame = undefined});

handle_message(tick, #ticker{media = Media, pos = Pos, frame = undefined, consumer = Consumer, stream_id = StreamId} = Ticker) ->
  Frame = ems_media:read_frame(Media, Pos),
  #video_frame{dts = NewDTS, next_id = NewPos} = Frame,
  Metadata = ems_media:metadata(Media),
  % ?D({tick, NewDTS, NewPos}),
  Consumer ! Metadata#video_frame{dts = NewDTS, pts = NewDTS, stream_id = StreamId},
  self() ! tick,
  
  TimerStart = element(1, erlang:statistics(wall_clock)),
  
  ?MODULE:loop(Ticker#ticker{pos = NewPos, dts = NewDTS, frame = Frame,
               timer_start = TimerStart, playing_from = NewDTS});
  
handle_message(tick, #ticker{media = Media, pos = Pos, dts = DTS, frame = PrevFrame, consumer = Consumer, stream_id = StreamId,
                             playing_from = PlayingFrom, timer_start = TimerStart, 
                             playing_till = PlayingTill, client_buffer = ClientBuffer} = Ticker) ->
  Consumer ! PrevFrame#video_frame{stream_id = StreamId},
  case ems_media:read_frame(Media, Pos) of
    eof ->
      % ?D(play_complete),
      Consumer ! {ems_stream, StreamId, play_complete, DTS},
      notify_about_stop(Ticker),
      ok;
    
    #video_frame{dts = NewDTS} when NewDTS >= PlayingTill ->
      % ?D({play_complete, DTS}),
      Consumer ! {ems_stream, StreamId, play_complete, DTS},
      notify_about_stop(Ticker),
      ok;
      
    #video_frame{dts = NewDTS, next_id = NewPos} = Frame ->
      Timeout = tick_timeout(NewDTS, PlayingFrom, TimerStart, ClientBuffer),
      Ticker1 = Ticker#ticker{pos = NewPos, dts = NewDTS, frame = Frame},
      receive
        Message ->
          ?MODULE:handle_message(Message, Ticker1)
      after
        Timeout -> 
          self() ! tick,  
          ?MODULE:loop(Ticker1)
      end
  end.


tick_timeout(DTS, PlayingFrom, TimerStart, ClientBuffer) ->
  {Now, _} = erlang:statistics(wall_clock),
  tick_timeout(DTS, PlayingFrom, TimerStart, Now, ClientBuffer).

tick_timeout(DTS, PlayingFrom, TimerStart, Now, ClientBuffer) ->
  NextTime = DTS - PlayingFrom,   %% Time from PlayingFrom in video timeline in which next frame should be seen
  RealTime = Now - TimerStart,    %% Wall clock from PlayingFrom
  Sleep = NextTime - RealTime - ClientBuffer,    %% Delta between next show time and current wall clock delta
  if
    Sleep < 0 -> 0;                %% This case means, that frame was too late. show it immediately
    ClientBuffer >= NextTime -> 0; %% We have seen less than buffer size from stream begin
    true -> round(Sleep)           %% Regular situation: we are far from stream begin, feed with frames
  end.


-include_lib("eunit/include/eunit.hrl").


timeout_in_buffer_from_start_test() ->
  ?assertEqual(0, tick_timeout(232, 0, 8, 10, 3000)).

timeout_in_buffer_after_seek_test() ->
  ?assertEqual(0, tick_timeout(10232, 10000, 8, 10, 3000)).

timeout_right_after_buffer_from_start_test() ->
  ?assertEqual(40, tick_timeout(3042, 0, 8, 10, 3000)).

timeout_right_after_buffer_after_seek_test() ->
  ?assertEqual(40, tick_timeout(13042, 10000, 8, 10, 3000)).










