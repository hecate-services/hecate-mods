%%% Bit flags for `room_state''s status field. Powers of 2, per
%%% evoq_bit_flags convention -- see reckon-db-org/evoq's guides/bit_flags.md
%%% and this workspace's own guide_mailbox_lifecycle (mailbox_status.hrl).
-define(ROOM_FORMED, 1). %% 2^0 -- moderate_room succeeded, the aggregate exists
-define(ROOM_ENDED,  2). %% 2^1 -- terminal, moderation has ended
