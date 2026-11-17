DROP TABLE IF EXISTS status_history, queue_entries, room_allocations, rounds,
    room_volunteers, candidates, users, rooms, companies CASCADE;

DROP FUNCTION IF EXISTS
    change_status(BIGINT, TEXT, BIGINT, INTEGER),
    change_evaluation(BIGINT, SMALLINT, TEXT, BIGINT, INTEGER),
    prevent_room_double_interview(),
    prevent_duplicate_candidate_round(),
    prevent_more_than_two_volunteers(),
    set_queue_updated_at(),
    require_audited_queue_change();
