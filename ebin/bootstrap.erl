#!/usr/bin/env escript

main(Args) ->
    [ScriptName,BeamDir,MainModule] = Args,

	Files = load_files("*.beam",BeamDir),
	
	case zip:create("mem", Files, [memory]) of 
		{ok, {"mem", ZipBin}} -> 
			%% Archive was successfully created. Prefix that binary with our
            		%% header and write to target file
                    Header = list_to_binary(string:join(["#!/usr/bin/env escript\n%%! -noshell -noinput -escript main",MainModule,"\n"]," ")),
            		Script = <<Header/binary, ZipBin/binary>>,
            		case file:write_file(ScriptName, Script) of
                		ok ->
                    			ok;
                		{error, WriteError} ->
                    			io:format("Failed to write ~s script: ~p\n", [ScriptName,WriteError]),
                    			halt(1)
            		end;
        	{error, ZipError} ->
            		io:format("Failed to construct ~s script archive: ~p\n", [ScriptName,ZipError]),
            		halt(1)
    	end,

	%% Finally, update executable perms for our script
    	case os:type() of
        	{unix,_} ->
            		[] = os:cmd(string:concat("chmod u+x ",ScriptName)),
            		ok;
        	_ ->
            		ok
    	end,
    
    	%% Add a helpful message
    	io:format("Congratulations! You now have a self-contained script called \"~s\" in\n"
              	"your current working directory. \n",[ScriptName]).

load_files(Wildcard, Dir) ->
	[ read_file(Filename, Dir) || Filename <- filelib:wildcard(Wildcard, Dir) ].

read_file(Filename, Dir) ->
	{ok, Bin} = file:read_file(filename:join(Dir, Filename)),
	{Filename, Bin}.

