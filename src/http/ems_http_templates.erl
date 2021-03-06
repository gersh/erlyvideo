-module(ems_http_templates).
-author('Max Lapshin <max@maxidoors.ru>').
-include("../../include/ems.hrl").

-export([http/4]).



http(Host, 'GET', [], Req) ->
  erlydtl:compile(ems_http:wwwroot(Host) ++ "/index.html", index_template),
  
  Query = Req:parse_qs(),
  ems_log:access(Host, "GET ~p ~s /", [Req:get(peer_addr), "-"]),
  
  File = proplists:get_value("file", Query, "video.mp4"),
  Autostart = proplists:get_value("autostart", Query, "true"),
  case file:list_dir(file_media:file_dir(Host)) of
    {ok, FileList} -> ok;
    {error, Error} -> 
      FileList = [],
      error_logger:error_msg("Invalid file_dir directory: ~p (~p)~n", [file_media:file_dir(Req:host()), Error])
  end,
  Secret = ems:get_var(secret_key, Host, undefined),
  {ok, Index} = index_template:render([
    {files, FileList},
    {hostname, <<"rtmp://", (Req:host())/binary>>},
    {autostart, Autostart},
    {live_id, uuid:to_string(uuid:v4())},
    {url, File},
    {session, json_session:encode([{channels, [10, 12]}, {user_id, 5}], Secret)}]),
  Req:ok([{'Content-Type', "text/html; charset=utf8"}], Index);


http(Host, 'GET', ["longtail"], Req) ->
  erlydtl:compile(ems_http:wwwroot(Host) ++ "/longtail/index.html", longtail_template),

  Query = Req:parse_qs(),
  io:format("GET /longtail/ ~p~n", [Query]),
  File = proplists:get_value("file", Query, "video.mp4"),
  Autostart = proplists:get_value("autostart", Query, "false"),
  Secret = ems:get_var(secret_key, Host, undefined),
  {ok, Index} = longtail_template:render([
    {hostname, <<"rtmp://", (Req:host())/binary>>},
    {autostart, Autostart},
    {file, File},
    {session, json_session:encode([{channels, [10, 12]}, {user_id, 5}], Secret)}]),
  Req:ok([{'Content-Type', "text/html; charset=utf8"}], Index);

http(Host, 'GET', ["admin.html"], Req) ->
  ok = erlydtl:compile(ems_http:wwwroot(Host) ++ "/admin.html", admin_template),
  Entries = [{Name, proplists:get_value(client_count, Options)} || {Name, _Pid, Options} <- media_provider:entries(Host)],
  {ok, Index} = admin_template:render([{entries, Entries}]),
  Req:ok([{'Content-Type', "text/html; charset=utf8"}], Index);

http(Host, 'GET', ["chat.html"], Req) ->
  erlydtl:compile(ems_http:wwwroot(Host) ++ "/chat.html", chat_template),
  Secret = ems:get_var(secret_key, Host, undefined),
  {ok, Index} = chat_template:render([
    {hostname, ems:get_var(host, Host, "rtmp://localhost")},
    {session, json_session:encode([{channels, [10, 12]}, {user_id, 5}], Secret)}
  ]),
  Req:ok([{'Content-Type', "text/html; charset=utf8"}], Index);

http(Host, 'GET', ["videoconf.html"], Req) ->
  erlydtl:compile(ems_http:wwwroot(Host) ++ "/videoconf.html", chat_template),
  Query = Req:parse_qs(),
  File = proplists:get_value("file", Query, "conference"),
  Secret = ems:get_var(secret_key, Host, undefined),
  {ok, Index} = chat_template:render([
    {hostname, ems:get_var(host, Host, "rtmp://localhost")},
    {url, File},
    {session, json_session:encode([{channels, [10, 12]}, {user_id, 5}], Secret)}
  ]),
  Req:ok([{'Content-Type', "text/html; charset=utf8"}], Index);


http(_Host, _Method, _Path, _Req) ->
  unhandled.
