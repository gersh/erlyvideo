-module(mp4_reader).
-author('Max Lapshin <max@maxidoors.ru>').

-behaviour(gen_format).
-include_lib("erlmedia/include/video_frame.hrl").
-include_lib("erlmedia/include/mp4.hrl").
-include("../../include/ems.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

-record(mp4_reader, {
  width,
  height,
  duration,
  audio_track,
  video_track,
  video_codec,
  audio_codec,
  audio_config,
  video_config,
  frames,
  reader,
  header
}).


-export([build_index_table/1, read_header/1]).

-export([init/1, read_frame/2, properties/1, seek/3, can_open_file/1, write_frame/2]).

-define(FRAMESIZE, 8).

can_open_file(Name) when is_binary(Name) ->
  can_open_file(binary_to_list(Name));

can_open_file(Name) ->
  filename:extension(Name) == ".mp4".

write_frame(_Device, _Frame) -> 
  erlang:error(unsupported).


codec_config(video, #mp4_reader{video_codec = VideoCodec} = MediaInfo) ->
  Config = decoder_config(video, MediaInfo),
  % ?D({"Video config", Config}),
  #video_frame{       
   	content = video,
   	flavor  = config,
		dts     = 0,
		pts     = 0,
		body    = Config,
		codec   = VideoCodec
	};

codec_config(audio, #mp4_reader{audio_codec = AudioCodec} = MediaInfo) ->
  Config = decoder_config(audio, MediaInfo),
  % ?D({"Audio config", aac:decode_config(Config)}),
  #video_frame{       
   	content = audio,
   	flavor  = config,
		dts     = 0,
		pts     = 0,
		body    = Config,
	  codec	  = AudioCodec,
	  sound   = {stereo, bit16, rate44}
	}.


first(Media) ->
  first(Media, 0, 0).

first(#mp4_reader{audio_config = A}, Id, DTS) when A =/= undefined ->
  {audio_config, Id, DTS};

first(#mp4_reader{video_config = V}, Id, DTS) when V =/= undefined ->
  {video_config, Id, DTS};

first(_, Id, _DTS) ->
  Id.


lookup_frame(video, #mp4_reader{video_track = VTs}) -> element(1,VTs);
lookup_frame(audio, #mp4_reader{audio_track = ATs}) -> element(1,ATs).


read_frame(MediaInfo, undefined) ->
  read_frame(MediaInfo, first(MediaInfo));

read_frame(MediaInfo, {audio_config, Pos, DTS}) ->
  % ?D({"Send audio config", Pos}),
  Frame = codec_config(audio, MediaInfo),
  Frame#video_frame{next_id = {video_config,Pos, DTS}, dts = DTS, pts = DTS};

read_frame(MediaInfo, {video_config,Pos, DTS}) ->
  % ?D({"Send video config", Pos}),
  Frame = codec_config(video, MediaInfo),
  Frame#video_frame{next_id = Pos, dts = DTS, pts = DTS};

read_frame(_, eof) ->
  eof;

read_frame(#mp4_reader{frames = Frames} = MediaInfo, Id) when Id*?FRAMESIZE < size(Frames)->
  % [{Id, Type, FrameId}] = ets:lookup(Frames, Id),
  FrameOffset = Id*?FRAMESIZE,
  <<_:FrameOffset/binary, Id:32, BinType:1, FrameId:31, _/binary>> = Frames,
  Type = case BinType of
    1 -> video;
    0 -> audio
  end,

  FrameTable = lookup_frame(Type, MediaInfo),
  Frame = mp4:read_frame(FrameTable, FrameId),
  #mp4_frame{offset = Offset, size = Size} = Frame,
  % Next = case ets:next(Frames, Id) of
  %   '$end_of_table' -> eof;
  %   NextId -> NextId
  % end,
  Next = if
    (Id+1)*?FRAMESIZE == size(Frames) -> eof;
    true -> Id + 1
  end,
    
  
	case read_data(MediaInfo, Offset, Size) of
		{ok, Data, _} -> 
		  VideoFrame = video_frame(Type, Frame, Data),
		  VideoFrame#video_frame{next_id = Next};
    eof -> eof;
    {error, Reason} -> {error, Reason}
  end.
  

read_data(#mp4_reader{reader = {M, Dev}} = MediaInfo, Offset, Size) ->
  case M:pread(Dev, Offset, Size) of
    {ok, Data} ->
      {ok, Data, MediaInfo};
    Else -> Else
  end.
  

seek(#mp4_reader{} = Media, before, Timestamp) when Timestamp == 0 ->
  {first(Media), 0};
  
seek(#mp4_reader{video_track = VTs, frames = Frames} = Media, Direction, Timestamp) ->
  FrameTable = element(1,VTs),
  case mp4:seek(FrameTable, Direction, Timestamp) of
    {VideoID, NewTimestamp} ->
      ID = find_by_frameid(Frames, video, VideoID),
      {first(Media, ID, NewTimestamp),NewTimestamp};
    undefined ->
      undefined
  end.


find_by_frameid(Frames, video, VideoID) ->
  find_by_frameid(Frames, 1, VideoID);
  
find_by_frameid(Frames, Type, FrameID) ->
  case Frames of
    <<ID:32, Type:1, FrameID:31, _/binary>> -> ID;
    <<_:64, Rest/binary>> -> find_by_frameid(Rest, Type, FrameID);
    <<>> -> undefined
  end.

  
  

video_frame(video, #mp4_frame{dts = DTS, keyframe = Keyframe, pts = PTS}, Data) ->
  #video_frame{
   	content = video,
		dts     = DTS,
		pts     = PTS,
		body    = Data,
		flavor  = case Keyframe of
		  true ->	keyframe;
		  _ -> frame
	  end,
		codec   = h264
  };  

video_frame(audio, #mp4_frame{dts = DTS}, Data) ->
  #video_frame{       
   	content = audio,
		dts     = DTS,
		pts     = DTS,
  	body    = Data,
  	flavor  = frame,
	  codec	  = aac,
	  sound	  = {stereo, bit16, rate44}
  }.



init(Reader) -> 
  Info1 = #mp4_reader{reader = Reader, audio_codec = aac, video_codec = h264},
  ?D("Going to read header"),
  % eprof:start(),
  % eprof:start_profiling([self()]),
  {Time, {ok, Info2}} = timer:tc(?MODULE, read_header, [Info1]),
  {Time2, {ok, Info3}} = timer:tc(?MODULE, build_index_table, [Info2]),
  ?D({"Time to parse moov and build index", round(Time/1000), round(Time2/1000), Info2#mp4_reader.duration}),
  % eprof:total_analyse(),
  % eprof:stop(),
  {ok, Info3}.

read_header(#mp4_reader{reader = Reader} = MediaInfo) -> 
  {ok, Mp4Media} = mp4:read_header(Reader),
  #mp4_media{width = Width, height = Height, audio_tracks = ATs, video_tracks = VTs, seconds = Seconds} = Mp4Media,
  ?D({"Opened mp4 file with following video tracks:", [Bitrate || #mp4_track{bitrate = Bitrate} <- VTs], "and audio tracks", [Language || #mp4_track{language = Language} <- ATs]}),
  AC = case ATs of
    [#mp4_track{decoder_config = ACC}|_] -> ACC;
    [] -> undefined
  end,
  VC = case VTs of
    [#mp4_track{decoder_config = VCC}|_] -> VCC;
    [] -> undefined
  end,
  Info1 = MediaInfo#mp4_reader{header = Mp4Media, width = Width, height = Height,            
                       audio_config = AC, video_config = VC, 
                       audio_track = list_to_tuple(ATs), video_track = list_to_tuple(VTs), duration = Seconds},
  {ok, Info1}.


track_by_number(Tracks, Number) when size(Tracks) < Number -> {undefined, 0};
track_by_number(Tracks, Number) -> {element(Number, Tracks), mp4:frame_count(element(Number, Tracks))}.


build_index_table(#mp4_reader{video_track = VTs, audio_track = ATs} = MediaInfo) ->
  {Video, VideoCount} = track_by_number(VTs, 1),
  {Audio, AudioCount} = track_by_number(ATs, 1),
  Index = <<>>,
  BuiltIndex = build_index_table(Video, 0, VideoCount, Audio, 0, AudioCount, Index, 0),
  {ok, MediaInfo#mp4_reader{frames = BuiltIndex}}.


build_index_table(_Video, VC, VC, _Audio, AC, AC, Index, _ID) ->
  Index;

build_index_table(Video, VC, VC, Audio, AudioID, AudioCount, Index, ID) ->
  % ets:insert(Index, {ID, audio, AudioID}),
  build_index_table(Video, VC, VC, Audio, AudioID+1, AudioCount, <<Index/binary, ID:32, 0:1, AudioID:31>>, ID+1);

build_index_table(Video, VideoID, VideoCount, Audio, AC, AC, Index, ID) ->
  % ets:insert(Index, {ID, video, VideoID}),
  build_index_table(Video, VideoID + 1, VideoCount, Audio, AC, AC, <<Index/binary, ID:32, 1:1, VideoID:31>>, ID+1);


build_index_table(Video, VideoID, VideoCount, Audio, AudioID, AudioCount, Index, ID) ->
  AFrame = mp4:read_frame(Audio, AudioID),
  VFrame = mp4:read_frame(Video, VideoID),
  case {VFrame#mp4_frame.dts, AFrame#mp4_frame.dts} of
    {VDTS, ADTS} when VDTS < ADTS ->
      % ets:insert(Index, {ID, video, VideoID}),
      build_index_table(Video, VideoID + 1, VideoCount, Audio, AudioID, AudioCount, <<Index/binary, ID:32, 1:1, VideoID:31>>, ID+1);
    {_VDTS, _ADTS} ->
      % ets:insert(Index, {ID, audio, AudioID}),
      build_index_table(Video, VideoID, VideoCount, Audio, AudioID + 1, AudioCount, <<Index/binary, ID:32, 0:1, AudioID:31>>, ID+1)
  end.


properties(#mp4_reader{width = Width, height = Height, duration = Duration, audio_track = ATs, video_track = VTs}) -> 
  Bitrates = [Bitrate || #mp4_track{bitrate = Bitrate} <- tuple_to_list(VTs)],
  Languages = [list_to_binary(Language) || #mp4_track{language = Language} <- tuple_to_list(ATs)],
  [{width, Width}, 
   {height, Height},
   {type, file},
   {duration, Duration/1000},
   {bitrates, Bitrates},
   {languages, Languages}].


decoder_config(video, #mp4_reader{video_config = DecoderConfig}) -> DecoderConfig;
decoder_config(audio, #mp4_reader{audio_config = DecoderConfig}) -> DecoderConfig.
