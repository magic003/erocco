-module(erocco).
-export([generate_documentation/1]).

-record(lang,
    {extension,
     name,
     symbol,
     comment_matcher, comment_filter,
     divider_text, divider_html}).

-define(LANGS,[
        #lang{extension=".coffee",name="coffee-script",symbol="#"},
        #lang{extension=".js",name="javascript",symbol="//"},
        #lang{extension=".rb",name="ruby",symbol="#"},
        #lang{extension=".py",name="python",symbol="#"},
        #lang{extension=".erl",name="erlang",symbol="%"}]).

-define(PYGMENTIZE,"pygmentize").
-define(PYGMENTIZE_URL,"http://pygments.appspot.com").
-define(HIGHLIGHT_START,"<div class=\"highlight\"><pre>").
-define(HIGHLIGHT_END,"</pre></div>").

-define(AMP,":amp:").
-define(SLASH, ":slash:").

generate_documentation(Source) ->
    Lang = get_language(Source),
    Lines = read_source(Source),
    Sections = parse(Lang,Lines),
    HighlightedSections = highlight(Lang,Sections),
    generate_html(Source,HighlightedSections).

parse(Lang, Lines) ->
    lists:reverse(parse(Lang, Lines, [], [], [])).

parse(_, [], DocsText, CodeText, Sections) -> 
    save_section(DocsText, CodeText, Sections);
parse(Lang, [L | Next], DocsText, CodeText, Sections) ->
    case {re:run(L,Lang#lang.comment_matcher,[{capture,none}]),
        re:run(L,Lang#lang.comment_filter,[{capture,none}])} of
        {match,nomatch} ->
            Doc = re:replace(L,Lang#lang.comment_matcher,"",[{return,list}]),
            case CodeText of
                [] -> parse(Lang,Next,[Doc | DocsText], CodeText, Sections);
                _  -> parse(Lang,Next,[Doc], [],save_section(DocsText,CodeText,Sections))
            end;
        _ -> parse(Lang,Next,DocsText,[L|CodeText],Sections)
    end.

highlight(Lang, Sections) ->
    Code = string:join([CodeText || {_,CodeText} <- Sections],Lang#lang.divider_text),
    ParentID = self(),
    PygmentID = spawn(fun() -> pygmentize(Lang,Code,ParentID) end), 
    MarkdownID = spawn(fun() -> markdown(Sections,ParentID) end),
    receive 
        {PygmentID, CodeHtml} -> CodeHtml
    end,
    receive
        {MarkdownID, DocSections} -> DocSections
    end,
    Fragments = re:split(
                    re:replace(
                        re:replace(CodeHtml,?HIGHLIGHT_START,"",[global]),
                        ?HIGHLIGHT_END,"",[global]),
                    Lang#lang.divider_html,[{return,list}]),
    lists:zipwith3(
        fun({DocsText,CodeText},DocSection,Fragment) ->
            {DocsText,CodeText,DocSection,?HIGHLIGHT_START ++ Fragment ++ ?HIGHLIGHT_END} end,
        Sections,DocSections,Fragments).

save_section(DocsText, CodeText, Sections) ->
    [{string:join(lists:reverse(DocsText),""),string:join(lists:reverse(CodeText),"")} | Sections].

read_source(Source) ->
    {ok, Device} = file:open(Source, [read, {encoding, utf8}]),
    Lines = read_lines(Device, []),
    file:close(Device),
    lists:reverse(Lines).

read_lines(IoDevice, Lines) ->
    case file:read_line(IoDevice) of
        {ok, Data} -> read_lines(IoDevice, [Data | Lines]);
        eof -> Lines
    end. 

languages() ->
    [ Lang#lang{comment_matcher="^\\s*" ++ Lang#lang.symbol ++ "\\s?",
                comment_filter="(^#![/]|^\\s*#\\{)",
                divider_text="\n" ++ Lang#lang.symbol ++ "DIVIDER\n",
                divider_html="\\n*<span class=\"c1?\">" ++ Lang#lang.symbol ++ "DIVIDER<\\/span>\\n*"} 
        || Lang <- ?LANGS ].

get_language(Source) -> get_language(filename:extension(Source), languages()).

get_language(Ext, []) -> 
    {error, "File extension " ++ Ext ++ " is not recognized."};
get_language(Ext, [H | _]) when Ext == H#lang.extension ->
    H;
get_language(Ext, [_ | T]) -> get_language(Ext, T).

is_pygmentize() ->
    case os:find_executable(?PYGMENTIZE) of
        false -> false;
        _ -> true
    end.

pygmentize(Lang,Code,ParentID) ->
    PygmentizeFun = case is_pygmentize() of
        true -> fun pygmentize_local/2;
        false -> 
            io:format("WARNING: Pygments not found. Using webservice."),
            fun pygmentize_webservice/2
    end,
    CodeHighlighted = PygmentizeFun(Lang,Code),
    ParentID ! {self(), CodeHighlighted}.
    

pygmentize_local(Lang,Code) -> {ok, Lang, Code}.

pygmentize_webservice(Lang,Code) ->
    inets:start(),
    case resolve_proxy() of 
        {Host,Port} -> httpc:set_options([{proxy, {{Host,Port},[]}}]);
        _ -> ok
    end,
    {ok, {_,_,Body}} = httpc:request(post,{?PYGMENTIZE_URL,[],"application/x-www-form-urlencoded","lang=" ++ Lang#lang.name ++ "&code=" ++ url_encode(Code)},[],[]),
    inets:stop(),
    Body.

resolve_proxy() ->
    case os:getenv("http_proxy") of
        false -> false;
        Proxy ->
            case re:split(Proxy,"//|:",[{return,list}]) of
                [_,[],Host,Port] -> {Host,list_to_integer(Port)};
                [_,[],Host] -> {Host,80}
            end
    end.

markdown(Sections,ParentID) ->
    DocSections = [markdown:conv_utf8(DocsText) || {DocsText,_} <- Sections],
    ParentID ! {self(), DocSections}.

-define(HEADER,"<!DOCTYPE html>
<html>
<head>
  <title>?title</title>
  <meta http-equiv=\"content-type\" content=\"text/html; charset=UTF-8\">
  <link rel=\"stylesheet\" media=\"all\" href=\"erocco.css\"/>
</head>
<body>
  <div id=\"container\">
    <div id=\"background\"></div>
    <table cellpadding=\"0\" cellspacing=\"0\">
      <thead>
        <tr>
          <th class=\"docs\">
            <h1>
              ?title
            </h1>
          </th>
          <th class=\"code\">
          </th>
        </tr>
      </thead>
      <tbody>").

-define(TABLE_ENTRY,"
<tr id=\"section-?index\">
<td class=\"docs\">
  <div class=\"pilwrap\">
    <a class=\"pilcrow\" href=\"#section-?index\">&#182;</a>
  </div>
  ?docs_html
</td>
<td class=\"code\">
  ?code_html
</td>
</tr>").

-define(FOOTER,"</tbody>
    </table>
  </div>
</body>
</html>").

-define(OUTDIR,"docs/").
 
generate_html(Source,HighlightedSections) ->
    ok = filelib:ensure_dir(?OUTDIR),
    Filename = ?OUTDIR ++ filename:basename(Source,filename:extension(Source)) ++ ".html",
    file:write_file(Filename,re:replace(?HEADER,"\\?title",filename:basename(Source),[global,{return,list}])),
    lists:mapfoldr(fun({_,_,DocsHtml,CodeHtml},Index) ->
                    T = re:replace(?TABLE_ENTRY,"\\?index",integer_to_list(Index),[global,{return,list}]),
                    T1 = re:replace(T,"\\?docs_html",replace_specials(DocsHtml),[global,{return,list}]),
                    T2 = re:replace(T1,"\\?code_html",replace_specials(CodeHtml),[global,{return,list}]),
                    file:write_file(Filename,restore_specials(T2),[append]),
                    {ok, Index + 1}
                end,
        1, HighlightedSections),
    file:write_file(Filename,?FOOTER,[append]),
    file:copy("priv/erocco.css",?OUTDIR ++ "erocco.css").


replace_specials(String) ->
    re:replace(re:replace(String,"&",?AMP,[global,{return,list}]),
                "\\\\",?SLASH,[global,{return,list}]).

restore_specials(String) ->
    re:replace(re:replace(String,?SLASH,"\\",[global,{return,list}]),
                ?AMP,"\\&",[global,{return,list}]).

url_encode([]) -> [];
url_encode([H|T]) when H==$;; H==$+; H==$& ->
    case integer_to_list(H,16) of
        [X, Y] -> [$%, X, Y | url_encode(T)];
        [X] -> [$%, $0, X | url_encode(T)]
    end;
url_encode([H|T]) ->
    [H | url_encode(T)].
