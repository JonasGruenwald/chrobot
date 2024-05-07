% FFI to interact with the browser via a port from erlang
% since gleam does not really support ports yet.
% ---

-module(chrobot_ffi).
-export([open_browser_port/2, send_to_port/2]).

% The port is openened with the option "nouse_stdio"
% which makes it use file descriptors 3 and 4 for stdin and stdout
% This is what chrome expects when started with --remote-debugging-pipe.
% A nice side effect of this is that chrome should will quit when the pipe is closed,
% avoiding the commmon port-related problem of zombie processes.
open_browser_port(Command, Args) ->
    PortName = {spawn_executable, Command},
    Options = [{args, Args}, binary, nouse_stdio, exit_status],
    try erlang:open_port(PortName, Options) of
        PortId ->
            erlang:link(PortId),
            {ok, PortId}
    catch
        error:Reason -> {error, Reason}
    end.

send_to_port(Port, BinaryString) ->
    try erlang:port_command(Port, BinaryString) of
        true -> {ok, true}
    catch
        error:Reason -> {error, Reason}
    end.
