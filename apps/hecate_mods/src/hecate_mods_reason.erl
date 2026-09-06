%%% @doc Renders an internal error term (an atom this domain's own
%%% guards/validators return, or anything else) as the binary a mesh
%%% RPC reply's `error' field carries. Shared so the three call sites
%%% that used to each carry their own byte-identical copy (Fable review,
%%% hecate-mods#5) can't drift.
-module(hecate_mods_reason).

-export([to_binary/1]).

-spec to_binary(term()) -> binary().
to_binary(R) when is_atom(R) -> atom_to_binary(R, utf8);
to_binary(R) when is_binary(R) -> R;
to_binary(R) -> iolist_to_binary(io_lib:format("~p", [R])).
