-- patch.sql: run once, after schema.sql and seed.sql.

-- 1. Fix the audit guard: in a fresh session current_setting() is NULL, so the old check never fired.
CREATE OR REPLACE FUNCTION require_audited_queue_change()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF (OLD.status, OLD.rating, OLD.outcome) IS DISTINCT FROM
       (NEW.status, NEW.rating, NEW.outcome)
       AND COALESCE(current_setting('app.audit_write', true), '') <> 'on' THEN
        RAISE EXCEPTION 'use change_status or change_evaluation to modify audited fields'
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    RETURN NEW;
END;
$$;

-- 2. change_status: volunteers only in their own room, room lock against simultaneous taps,
--    coordinator can undo one step (undo clears rating/outcome).
CREATE OR REPLACE FUNCTION change_status(
    p_queue_entry_id BIGINT,
    p_new_status TEXT,
    p_user_id BIGINT,
    p_expected_version INTEGER DEFAULT NULL
)
RETURNS queue_entries LANGUAGE plpgsql AS $$
DECLARE
    v_entry queue_entries;
    v_old   queue_entries;
    v_role  TEXT;
    v_room  BIGINT;
BEGIN
    SELECT * INTO v_entry FROM queue_entries
    WHERE queue_entry_id = p_queue_entry_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'queue entry % not found', p_queue_entry_id; END IF;

    SELECT role INTO v_role FROM users WHERE user_id = p_user_id;
    IF v_role IS NULL OR v_role NOT IN ('room_volunteer', 'coordinator') THEN
        RAISE EXCEPTION 'user % is not authorized to change status', p_user_id
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF p_new_status NOT IN ('In queue', 'Interviewing', 'Done') THEN
        RAISE EXCEPTION 'invalid status: %', p_new_status USING ERRCODE = 'check_violation';
    END IF;

    SELECT room_id INTO v_room FROM room_allocations WHERE allocation_id = v_entry.allocation_id;
    IF v_role = 'room_volunteer' AND NOT EXISTS (
        SELECT 1 FROM room_volunteers WHERE room_id = v_room AND user_id = p_user_id) THEN
        RAISE EXCEPTION 'user % is not assigned to room %', p_user_id, v_room
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF p_expected_version IS NOT NULL AND v_entry.version <> p_expected_version THEN
        RAISE EXCEPTION 'stale version: expected %, actual %', p_expected_version, v_entry.version
            USING ERRCODE = 'serialization_failure';
    END IF;

    IF NOT ((v_entry.status = 'In queue' AND p_new_status = 'Interviewing')
         OR (v_entry.status = 'Interviewing' AND p_new_status = 'Done')
         OR v_entry.status = p_new_status
         OR (v_role = 'coordinator' AND
             ((v_entry.status = 'Interviewing' AND p_new_status = 'In queue')
           OR (v_entry.status = 'Done' AND p_new_status = 'Interviewing')))) THEN
        RAISE EXCEPTION 'invalid status transition: % -> %', v_entry.status, p_new_status
            USING ERRCODE = 'check_violation';
    END IF;
    IF v_entry.status = p_new_status THEN RETURN v_entry; END IF;

    -- One interview per room: lock the room so two simultaneous taps cannot both pass.
    IF p_new_status = 'Interviewing' THEN
        PERFORM 1 FROM rooms WHERE room_id = v_room FOR NO KEY UPDATE;
    END IF;

    v_old := v_entry;
    PERFORM set_config('app.audit_write', 'on', true);
    UPDATE queue_entries
    SET status  = p_new_status,
        rating  = CASE WHEN p_new_status = 'Done' THEN rating END,
        outcome = CASE WHEN p_new_status = 'Done' THEN outcome END,
        version = version + 1
    WHERE queue_entry_id = p_queue_entry_id RETURNING * INTO v_entry;
    INSERT INTO status_history(queue_entry_id, changed_by, old_status, new_status,
                               old_rating, new_rating, old_outcome, new_outcome, remark)
    VALUES (p_queue_entry_id, p_user_id, v_old.status, v_entry.status,
            v_old.rating, v_entry.rating, v_old.outcome, v_entry.outcome, 'Status change');
    PERFORM set_config('app.audit_write', 'off', true);
    RETURN v_entry;
END;
$$;

-- 3. Functions must not be callable through the public API.
REVOKE EXECUTE ON FUNCTION
    change_status(BIGINT, TEXT, BIGINT, INTEGER),
    change_evaluation(BIGINT, SMALLINT, TEXT, BIGINT, INTEGER)
FROM PUBLIC, anon, authenticated;

-- 4. Readable constraint names, rating only when Done, remove duplicate unique key.
ALTER TABLE queue_entries RENAME CONSTRAINT queue_entries_check TO outcome_requires_done;
ALTER TABLE queue_entries ADD CONSTRAINT rating_requires_done
    CHECK (rating IS NULL OR status = 'Done');
ALTER TABLE room_volunteers DROP CONSTRAINT IF EXISTS room_volunteers_room_id_user_id_key;
