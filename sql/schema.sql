-- Campus placement operations schema for Supabase / PostgreSQL 15+

CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE companies (
    company_id   BIGSERIAL PRIMARY KEY,
    company_name TEXT NOT NULL UNIQUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE users (
    user_id    BIGSERIAL PRIMARY KEY,
    full_name  TEXT NOT NULL,
    email      TEXT NOT NULL UNIQUE,
    role       TEXT NOT NULL CHECK (role IN ('room_volunteer', 'recruiter', 'coordinator')),
    company_id BIGINT REFERENCES companies(company_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (role <> 'recruiter' OR company_id IS NOT NULL),
    CHECK (role = 'recruiter' OR company_id IS NULL)
);

CREATE TABLE rooms (
    room_id   BIGSERIAL PRIMARY KEY,
    room_name TEXT NOT NULL UNIQUE
);

CREATE TABLE room_volunteers (
    room_id BIGINT NOT NULL REFERENCES rooms(room_id) ON DELETE CASCADE,
    user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (room_id, user_id),
    UNIQUE (room_id, user_id)
);

CREATE TABLE candidates (
    candidate_id     BIGSERIAL PRIMARY KEY,
    full_name        TEXT NOT NULL,
    email            TEXT NOT NULL UNIQUE,
    phone            TEXT NOT NULL UNIQUE,
    college          TEXT NOT NULL,
    graduation_year  INTEGER NOT NULL CHECK (graduation_year BETWEEN 2020 AND 2100),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE rounds (
    round_id     BIGSERIAL PRIMARY KEY,
    company_id   BIGINT NOT NULL REFERENCES companies(company_id),
    round_number INTEGER NOT NULL CHECK (round_number > 0),
    round_name   TEXT,
    UNIQUE (company_id, round_number)
);

CREATE TABLE room_allocations (
    allocation_id BIGSERIAL PRIMARY KEY,
    room_id       BIGINT NOT NULL REFERENCES rooms(room_id),
    round_id      BIGINT NOT NULL REFERENCES rounds(round_id),
    slot_start    TIMESTAMPTZ NOT NULL,
    slot_end      TIMESTAMPTZ NOT NULL,
    CHECK (slot_end > slot_start),
    CONSTRAINT room_allocations_room_time_no_overlap EXCLUDE USING gist (
        room_id WITH =,
        tstzrange(slot_start, slot_end, '[)') WITH &&
    )
);

CREATE TABLE queue_entries (
    queue_entry_id BIGSERIAL PRIMARY KEY,
    candidate_id   BIGINT NOT NULL REFERENCES candidates(candidate_id),
    allocation_id  BIGINT NOT NULL REFERENCES room_allocations(allocation_id),
    status         TEXT NOT NULL DEFAULT 'In queue'
        CHECK (status IN ('In queue', 'Interviewing', 'Done')),
    rating         SMALLINT CHECK (rating IS NULL OR rating BETWEEN 1 AND 5),
    outcome        TEXT CHECK (outcome IS NULL OR outcome IN ('Shortlisted', 'Rejected', 'On hold')),
    remark         TEXT,
    version        INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (candidate_id, allocation_id),
    CHECK (outcome IS NULL OR status = 'Done')
);

-- A candidate may be queued for multiple companies, but only one active interview.
CREATE UNIQUE INDEX one_active_interview_per_candidate
    ON queue_entries(candidate_id)
    WHERE status = 'Interviewing';

-- allocation_id is the only room reference on queue_entries. PostgreSQL does
-- not permit a cross-table subquery in an index expression, so this equivalent
-- room-level partial uniqueness rule is enforced by a trigger.
CREATE UNIQUE INDEX one_active_interview_per_allocation
    ON queue_entries(allocation_id)
    WHERE status = 'Interviewing';

CREATE TABLE status_history (
    status_history_id BIGSERIAL PRIMARY KEY,
    queue_entry_id    BIGINT NOT NULL REFERENCES queue_entries(queue_entry_id),
    changed_by        BIGINT NOT NULL REFERENCES users(user_id),
    old_status        TEXT,
    new_status        TEXT,
    old_rating        SMALLINT,
    new_rating        SMALLINT,
    old_outcome       TEXT,
    new_outcome       TEXT,
    changed_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    remark            TEXT,
    CHECK (old_status IS DISTINCT FROM new_status
        OR old_rating IS DISTINCT FROM new_rating
        OR old_outcome IS DISTINCT FROM new_outcome)
);

CREATE INDEX queue_entries_allocation_id_idx ON queue_entries(allocation_id);
CREATE INDEX room_allocations_room_id_idx ON room_allocations(room_id);
CREATE INDEX status_history_queue_entry_id_idx ON status_history(queue_entry_id);

CREATE OR REPLACE FUNCTION prevent_room_double_interview()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status = 'Interviewing' AND EXISTS (
        SELECT 1
        FROM queue_entries q
        JOIN room_allocations existing_a ON existing_a.allocation_id = q.allocation_id
        JOIN room_allocations new_a ON new_a.allocation_id = NEW.allocation_id
        WHERE q.status = 'Interviewing'
          AND existing_a.room_id = new_a.room_id
          AND q.queue_entry_id <> NEW.queue_entry_id
    ) THEN
        RAISE EXCEPTION 'room % already has an interviewing candidate',
            (SELECT room_id FROM room_allocations WHERE allocation_id = NEW.allocation_id)
            USING ERRCODE = 'unique_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER queue_entries_one_interview_per_room
BEFORE INSERT OR UPDATE OF status, allocation_id ON queue_entries
FOR EACH ROW EXECUTE FUNCTION prevent_room_double_interview();

CREATE OR REPLACE FUNCTION prevent_duplicate_candidate_round()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM queue_entries q
        JOIN room_allocations a ON a.allocation_id = q.allocation_id
        JOIN room_allocations new_a ON new_a.allocation_id = NEW.allocation_id
        WHERE q.candidate_id = NEW.candidate_id
          AND a.round_id = new_a.round_id
          AND q.queue_entry_id <> NEW.queue_entry_id
    ) THEN
        RAISE EXCEPTION 'candidate % already has an entry in round %',
            NEW.candidate_id,
            (SELECT a.round_id FROM room_allocations a WHERE a.allocation_id = NEW.allocation_id)
            USING ERRCODE = 'unique_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER queue_entries_one_candidate_per_round
BEFORE INSERT OR UPDATE OF candidate_id, allocation_id ON queue_entries
FOR EACH ROW EXECUTE FUNCTION prevent_duplicate_candidate_round();

CREATE OR REPLACE FUNCTION prevent_more_than_two_volunteers()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF (SELECT count(*) FROM room_volunteers WHERE room_id = NEW.room_id) >= 2 THEN
        RAISE EXCEPTION 'room % already has two volunteers', NEW.room_id
            USING ERRCODE = 'check_violation';
    END IF;
    IF (SELECT role FROM users WHERE user_id = NEW.user_id) <> 'room_volunteer' THEN
        RAISE EXCEPTION 'user % is not a room volunteer', NEW.user_id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER room_volunteers_max_two
BEFORE INSERT ON room_volunteers
FOR EACH ROW EXECUTE FUNCTION prevent_more_than_two_volunteers();

CREATE OR REPLACE FUNCTION set_queue_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE TRIGGER queue_entries_set_updated_at
BEFORE UPDATE ON queue_entries
FOR EACH ROW EXECUTE FUNCTION set_queue_updated_at();

-- Prevent direct edits to audited fields. The two mutation functions below set
-- this transaction-local flag immediately before their controlled UPDATE.
CREATE OR REPLACE FUNCTION require_audited_queue_change()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF (OLD.status, OLD.rating, OLD.outcome) IS DISTINCT FROM
       (NEW.status, NEW.rating, NEW.outcome)
       AND current_setting('app.audit_write', true) <> 'on' THEN
        RAISE EXCEPTION 'use change_status or change_evaluation to modify audited fields'
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER queue_entries_require_audit
BEFORE UPDATE ON queue_entries
FOR EACH ROW EXECUTE FUNCTION require_audited_queue_change();

CREATE OR REPLACE FUNCTION change_status(
    p_queue_entry_id BIGINT,
    p_new_status TEXT,
    p_user_id BIGINT,
    p_expected_version INTEGER DEFAULT NULL
)
RETURNS queue_entries LANGUAGE plpgsql AS $$
DECLARE
    v_entry queue_entries;
    v_role TEXT;
    v_old_status TEXT;
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
    IF p_expected_version IS NOT NULL AND v_entry.version <> p_expected_version THEN
        RAISE EXCEPTION 'stale version: expected %, actual %', p_expected_version, v_entry.version
            USING ERRCODE = 'serialization_failure';
    END IF;
    IF NOT ((v_entry.status = 'In queue' AND p_new_status = 'Interviewing') OR
            (v_entry.status = 'Interviewing' AND p_new_status = 'Done') OR
            (v_entry.status = p_new_status)) THEN
        RAISE EXCEPTION 'invalid status transition: % -> %', v_entry.status, p_new_status
            USING ERRCODE = 'check_violation';
    END IF;
    IF v_entry.status = p_new_status THEN RETURN v_entry; END IF;
    v_old_status := v_entry.status;
    PERFORM set_config('app.audit_write', 'on', true);
    UPDATE queue_entries SET status = p_new_status, version = version + 1
    WHERE queue_entry_id = p_queue_entry_id RETURNING * INTO v_entry;
    INSERT INTO status_history(queue_entry_id, changed_by, old_status, new_status,
                               old_rating, new_rating, old_outcome, new_outcome, remark)
    VALUES (p_queue_entry_id, p_user_id, v_old_status, v_entry.status,
            v_entry.rating, v_entry.rating, v_entry.outcome, v_entry.outcome, 'Status change');
    PERFORM set_config('app.audit_write', 'off', true);
    RETURN v_entry;
END;
$$;

CREATE OR REPLACE FUNCTION change_evaluation(
    p_queue_entry_id BIGINT,
    p_rating SMALLINT,
    p_outcome TEXT,
    p_user_id BIGINT,
    p_expected_version INTEGER DEFAULT NULL
)
RETURNS queue_entries LANGUAGE plpgsql AS $$
DECLARE
    v_entry queue_entries;
    v_role TEXT;
    v_company BIGINT;
    v_old_rating SMALLINT;
    v_old_outcome TEXT;
BEGIN
    SELECT q.* INTO v_entry FROM queue_entries q
    WHERE q.queue_entry_id = p_queue_entry_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'queue entry % not found', p_queue_entry_id; END IF;
    SELECT u.role, u.company_id INTO v_role, v_company FROM users u WHERE u.user_id = p_user_id;
    IF v_role IS NULL OR v_role NOT IN ('recruiter', 'coordinator') THEN
        RAISE EXCEPTION 'user % is not authorized to rate candidates', p_user_id
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF v_role = 'recruiter' AND v_company <> (SELECT r.company_id FROM rounds r
        JOIN room_allocations a ON a.round_id = r.round_id
        WHERE a.allocation_id = v_entry.allocation_id) THEN
        RAISE EXCEPTION 'recruiter % is not assigned to this company', p_user_id
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF v_entry.status <> 'Done' THEN
        RAISE EXCEPTION 'evaluation requires status Done' USING ERRCODE = 'check_violation';
    END IF;
    IF p_rating IS NOT NULL AND (p_rating < 1 OR p_rating > 5) THEN
        RAISE EXCEPTION 'rating must be between 1 and 5' USING ERRCODE = 'check_violation';
    END IF;
    IF p_outcome IS NOT NULL AND p_outcome NOT IN ('Shortlisted', 'Rejected', 'On hold') THEN
        RAISE EXCEPTION 'invalid outcome: %', p_outcome USING ERRCODE = 'check_violation';
    END IF;
    IF p_expected_version IS NOT NULL AND v_entry.version <> p_expected_version THEN
        RAISE EXCEPTION 'stale version: expected %, actual %', p_expected_version, v_entry.version
            USING ERRCODE = 'serialization_failure';
    END IF;
    v_old_rating := v_entry.rating;
    v_old_outcome := v_entry.outcome;
    PERFORM set_config('app.audit_write', 'on', true);
    UPDATE queue_entries SET rating = p_rating, outcome = p_outcome, version = version + 1
    WHERE queue_entry_id = p_queue_entry_id RETURNING * INTO v_entry;
    INSERT INTO status_history(queue_entry_id, changed_by, old_status, new_status,
                               old_rating, new_rating, old_outcome, new_outcome, remark)
    VALUES (p_queue_entry_id, p_user_id, v_entry.status, v_entry.status,
            v_old_rating, v_entry.rating, v_old_outcome, v_entry.outcome, 'Evaluation change');
    PERFORM set_config('app.audit_write', 'off', true);
    RETURN v_entry;
END;
$$;

