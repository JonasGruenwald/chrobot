-module(chrobot_ffi).
-include_lib("kernel/include/file.hrl").
-export([open_browser_port/2, send_to_port/2, get_arch/0, unzip/2, set_executable/1, run_command/1, get_time_ms/0]).

% ---------------------------------------------------
% RUNTIME
% ---------------------------------------------------

% FFI to interact with the browser via a port from erlang
% since gleam does not really support ports yet.
% module: chrobot/chrome.gleam

% The port is opened with the option "nouse_stdio"
% which makes it use file descriptors 3 and 4 for stdin and stdout
% This is what chrome expects when started with --remote-debugging-pipe.
% A nice side effect of this is that chrome should quit when the pipe is closed,
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

% ---------------------------------------------------
% INSTALLER
% ---------------------------------------------------

% Utils for the installer script
% module: chrobot/install.gleam

% Get the architecture of the system
get_arch() ->
    ArchCharlist = erlang:system_info(system_architecture),
    list_to_binary(ArchCharlist).

% Run a shell command and return the output
run_command(Command) ->
    CommandList = binary_to_list(Command),
    list_to_binary(os:cmd(CommandList)).

% Unzip a file to a directory using the erlang stdlib zip module
unzip(ZipFile, DestDir) ->
    ZipFileCharlist = binary_to_list(ZipFile),
    DestDirCharlist = binary_to_list(DestDir),
    try zip:unzip(ZipFileCharlist, [{cwd, DestDirCharlist}]) of
        {ok, _FileList} ->
            {ok, nil};
        {error, _} = Error ->
            Error
    catch
        _:Reason ->
            {error, Reason}
    end.

% Set the executable bit on a file
set_executable(FilePath) ->
    FileInfo = file:read_file_info(FilePath),
    case FileInfo of
        {ok, FI} ->
            NewFI = FI#file_info{mode = 8#755},
            case file:write_file_info(FilePath, NewFI) of
                ok -> {ok, nil};
                {error, _} = Error -> Error
            end;
        {error, Reason} ->
            {error, Reason}
    end.

% ---------------------------------------------------
% UTILITIES
% ---------------------------------------------------

% Miscelaneous utilities
% module: chrobot/internal/utils.gleam

get_time_ms() ->
    os:system_time(millisecond).