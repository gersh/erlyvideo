-module(ems_http_mpegts).
-author('Max Lapshin <max@maxidoors.ru>').
-include("../../include/ems.hrl").

-export([http/4]).



handle(Host, 'GET', Path, Req) ->
  FileName = filename:absname(filename:join([wwwroot(Host) | Path])),
  case filelib:is_regular(FileName) of
    true ->
      ems_log:access(Host, "GET ~p ~s /~s", [Req:get(peer_addr), "-", string:join(Path, "/")]),
      Req:file(FileName);
    false ->
      unhandled
  end;


http(_Host, _Method, _Path, _Req) ->
  unhandled.
