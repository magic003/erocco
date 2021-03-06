%%% **Erocco** is a quick-and-dirty, hundred-line-long, literate-programming-
%%% style documentation generator. It produces HTML that displays your comments
%%% alongside your code. Comments are passed through
%%% [Markdown](http://daringfireball.net/projects/markdown/syntax), and code is
%%% passed through [Pygments](http://pygments.org/) syntax highlighting.
%%% This page is the result of running Erocco against its own source file.
%%% 
%%% If you install Erocco, you can run it from the command-line:
%%%
%%%     erocco src/*.erl 
%%%
%%% ...will generate an HTML documentation page for each of the named source 
%%% files, with a menu linking to other pages, saving it into a `docs` folder.
%%% 
%%% The [source for Erocco](http://github.com/magic003/erocco) is available on
%%% GitHub, and released under the MIT license.
%%% 
%%% For its syntax highlighting Erocco relies on 
%%% [Pygments](http://pyments.org/). It is called either through a local 
%%% installation or remote [web service](http://pygments.appspot.com). As a 
%%% markdown engine it ships with Gordon Guthrie's 
%%% [erlmarkdown](http://github.com/gordonguthrie/erlmarkdown). Otherwise there
%%% are no external dependencies.

-module(erocco).
-export([generate_documentation/1]).

%% ### Record & Macros

%% Programming language record.
-record(lang,
    {extension,
     name,
     symbol,
     comment_matcher, comment_filter,
     divider_text, divider_html}).

%% Supported languages.
-define(LANGS,[
        #lang{extension=".coffee",name="coffee-script",symbol="#"},
        #lang{extension=".js",name="javascript",symbol="//"},
        #lang{extension=".rb",name="ruby",symbol="#"},
        #lang{extension=".py",name="python",symbol="#"},
        #lang{extension=".erl",name="erlang",symbol="%"}]).

%% Pygments executable name.
-define(PYGMENTIZE,"pygmentize").
%% Pygments web service URL.
-define(PYGMENTIZE_URL,"http://pygments.appspot.com").

%% The start of each Pygments highlight block.
-define(HIGHLIGHT_START,"<div class=\"highlight\"><pre>").
%% The end of each Pygments highlight block.
-define(HIGHLIGHT_END,"</pre></div>").

%% The output html templates.
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
    ?jump
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

-define(JUMP_START,"
<div id=\"jump_to\">
  Jump To \\&hellip;
  <div id=\"jump_wrapper\">
  <div id=\"jump_page\">").

-define(JUMP,"
  <a class=\"source\" href=\"?jump_html\">?jump_file</a>").

-define(JUMP_END,"
    </div>
  </div>
</div>").

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

%% Placeholders for special characters.
-define(AMP,":amp:").
-define(SLASH, ":slash:").

%% Output directory.
-define(OUTDIR,"docs/").
 

%% ### Main Documentation Generation Functions

%% Generate the documentation for source files specified using a Unix
%% wildcard style.
generate_documentation(Sources) ->
    case Sources of
        [H] -> generate_documentation([H],"");
        [H|N] ->
            Jump = generate_jump([H|N],[],get_language(H)),
            generate_documentation([H|N],Jump);
        [] -> ok
    end.

%% Generate the documentation for a source file by reading it in, splitting it
%% up into comment/code sections, highlighting them for appropriate languages,
%% and merging them into an HTML template.
generate_documentation([],_) -> ok;
generate_documentation([Source|Next], Jump) ->
    Lang = get_language(Source),
    Lines = read_source(Source),
    Sections = parse(Lang,Lines),
    HighlightedSections = highlight(Lang,Sections),
    File = generate_html(Source,HighlightedSections,Jump),
    io:format("File ~s is generated.~n",[File]),
    generate_documentation(Next,Jump).

%% Given lines of source code, parse out each comment and the code that
%% follows it, and create an individual section for it. Sections take the form:
%% 
%%      {
%%        docs\_text: ...,
%%        docs\_html: ...,
%%        code\_text: ...,
%%        code\_html: ...
%%      }
%% 
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

%% Loop through a table of split sections, pass the code through **Pygments**
%% and convert the document from **Markdown** to HTML. Add docs\_html and 
%% code\_html to the sections
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

%% After the highlighting is done, the template is filled with documentation
%% and code snippets and an HTML file is written.
generate_html(Source,HighlightedSections,Jump) ->
    ok = filelib:ensure_dir(?OUTDIR),
    Filename = ?OUTDIR ++ filename:basename(Source,filename:extension(Source)) ++ ".html",
    file:write_file(Filename,re:replace(
            re:replace(?HEADER,"\\?title",
                filename:basename(Source),[global,{return,list}]),
            "\\?jump",Jump,[global,{return,list}])),
    lists:mapfoldl(fun({_,_,DocsHtml,CodeHtml},Index) ->
                    T = re:replace(?TABLE_ENTRY,"\\?index",integer_to_list(Index),[global,{return,list}]),
                    T1 = re:replace(T,"\\?docs_html",replace_specials(DocsHtml),[global,{return,list}]),
                    T2 = re:replace(T1,"\\?code_html",replace_specials(CodeHtml),[global,{return,list}]),
                    file:write_file(Filename,restore_specials(T2),[append]),
                    {ok, Index + 1}
                end,
        1, HighlightedSections),
    file:write_file(Filename,?FOOTER,[append]),
    file:copy("priv/erocco.css",?OUTDIR ++ "erocco.css"),
    Filename.

%% ### Helpers

%% Read a source file by lines.
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

%% Save docs\_html and code\_html to a table of split sections.
save_section(DocsText, CodeText, Sections) ->
    [{string:join(lists:reverse(DocsText),""),string:join(lists:reverse(CodeText),"")} | Sections].

%% Get a list of supported languages, including file extension, name,
%% comment symbol and etc.
languages() ->
    [ Lang#lang{comment_matcher="^\\s*" ++ Lang#lang.symbol ++ "+\\s?",
                comment_filter="(^#![/]|^\\s*#\\{)",
                divider_text="\n" ++ Lang#lang.symbol ++ "DIVIDER\n",
                divider_html="\\n*<span class=\"c1?\">" ++ Lang#lang.symbol ++ "DIVIDER<\\/span>\\n*"} 
        || Lang <- ?LANGS ].

%% Get the language from the extenstion of a source file.
get_language(Source) -> get_language(filename:extension(Source), languages()).

get_language(Ext, []) -> 
    {error, "File extension " ++ Ext ++ " is not recognized."};
get_language(Ext, [H | _]) when Ext == H#lang.extension ->
    H;
get_language(Ext, [_ | T]) -> get_language(Ext, T).

%% Test if Pygments is installed on the local machine.
is_pygmentize() ->
    case os:find_executable(?PYGMENTIZE) of
        false -> false;
        _ -> true
    end.
%% Use Pygments to highlight the source code. It calls the executable file
%% if it is installed locally. Otherwise, it invokes the web service.
pygmentize(Lang,Code,ParentID) ->
    PygmentizeFun = case is_pygmentize() of
        true -> fun pygmentize_local/2;
        false -> 
            io:format("WARNING: Pygments not found. Using webservice."),
            fun pygmentize_webservice/2
    end,
    CodeHighlighted = PygmentizeFun(Lang,Code),
    ParentID ! {self(), CodeHighlighted}.

%% Calls the Pygments executable to highlight the code. A temporary file
%% which only contains the source code is created as the input.
pygmentize_local(Lang,Code) -> 
    TmpFile = get_tmpfile(Lang),
    file:write_file(TmpFile,Code),
    Res = os:cmd(
            ?PYGMENTIZE ++ " -l " ++ Lang#lang.name ++ 
            " -O encoding=utf-8 -f html " ++ TmpFile),
    file:delete(TmpFile),
    Res.

get_tmpfile(Lang) ->
    {MgSecs,Secs,MiSecs} = now(),
    lists:flatten(io_lib:format("~p_~p_~p~s",
                                [MgSecs,Secs,MiSecs,Lang#lang.extension])).

%% Calls Pygments web service to highlight the source code. Proxy can
%% be specified in environment variable _http_____proxy_.
pygmentize_webservice(Lang,Code) ->
    inets:start(),
    case resolve_proxy() of 
        {Host,Port} -> httpc:set_options([{proxy, {{Host,Port},[]}}]);
        _ -> ok
    end,
    {ok, {_,_,Body}} = httpc:request(post,
                        {?PYGMENTIZE_URL,[],
                        "application/x-www-form-urlencoded",
                        "lang=" ++ Lang#lang.name ++ "&code=" ++ url_encode(Code)},
                        [],[]),
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

%% URL encode the content.
url_encode([]) -> [];
url_encode([H|T]) when H==$;; H==$+; H==$& ->
    case integer_to_list(H,16) of
        [X, Y] -> [$%, X, Y | url_encode(T)];
        [X] -> [$%, $0, X | url_encode(T)]
    end;
url_encode([H|T]) ->
    [H | url_encode(T)].

%% Use Gordon Guthrie's 
%% [erlmarkdown](http://github.com/gordonguthrie/erlmarkdown) to generate
%% the documentation.
markdown(Sections,ParentID) ->
    DocSections = [markdown:conv_utf8(DocsText) || {DocsText,_} <- Sections],
    ParentID ! {self(), DocSections}.

%% Characters & and \\ are special in Erlang regular expression. Replace
%% and restore them with placeholders to escape them.
replace_specials(String) ->
    re:replace(re:replace(String,"&",?AMP,[global,{return,list}]),
                "\\\\",?SLASH,[global,{return,list}]).

restore_specials(String) ->
    re:replace(re:replace(String,?SLASH,"\\",[global,{return,list}]),
                ?AMP,"\\&",[global,{return,list}]).

%% Generate the jump section of the html documentations.
generate_jump([],JumpEntries,_) ->
    ?JUMP_START ++ lists:flatten(JumpEntries) ++ ?JUMP_END;
generate_jump([H|N],JumpEntries,Lang) ->
    Basename = filename:basename(H,Lang#lang.extension),
    JumpEntry = re:replace(
                    re:replace(?JUMP,"\\?jump_html",
                        Basename ++ ".html",
                        [global,{return,list}]),
                    "\\?jump_file",filename:basename(H),[global,{return,list}]),
    generate_jump(N,[JumpEntry | JumpEntries],Lang).
