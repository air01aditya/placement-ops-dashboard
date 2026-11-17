-- tests.sql: run after schema.sql, seed.sql and patch.sql. Re-run seed.sql before each test run.

CREATE OR REPLACE FUNCTION pg_temp.expect_error(p_name TEXT, p_sql TEXT, p_state TEXT, p_like TEXT)
RETURNS TEXT LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    RETURN 'FAIL  ' || p_name || ': no error was raised';
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = p_state AND SQLERRM LIKE p_like THEN
        RETURN 'PASS  ' || p_name || '  ->  ' || SQLERRM;
    END IF;
    RETURN 'FAIL  ' || p_name || '  ->  got ' || SQLSTATE || ': ' || SQLERRM;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.expect_ok(p_name TEXT, p_sql TEXT)
RETURNS TEXT LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    RETURN 'PASS  ' || p_name;
EXCEPTION WHEN OTHERS THEN
    RETURN 'FAIL  ' || p_name || '  ->  ' || SQLSTATE || ': ' || SQLERRM;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.expect_true(p_name TEXT, p_sql TEXT)
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE v BOOLEAN;
BEGIN
    EXECUTE p_sql INTO v;
    RETURN CASE WHEN v THEN 'PASS  ' ELSE 'FAIL  ' END || p_name;
END;
$$;

-- Look up ids by meaning instead of hard-coding them.
CREATE OR REPLACE FUNCTION pg_temp.entry(p_cand INT, p_comp INT) RETURNS BIGINT LANGUAGE sql AS $$
    SELECT q.queue_entry_id
    FROM queue_entries q
    JOIN room_allocations a ON a.allocation_id = q.allocation_id
    JOIN rounds r ON r.round_id = a.round_id
    WHERE q.candidate_id = p_cand AND r.company_id = p_comp AND r.round_number = 1
$$;
CREATE OR REPLACE FUNCTION pg_temp.volunteer(p_room INT) RETURNS BIGINT LANGUAGE sql AS $$
    SELECT user_id FROM room_volunteers WHERE room_id = p_room ORDER BY user_id LIMIT 1
$$;
CREATE OR REPLACE FUNCTION pg_temp.recruiter(p_comp INT) RETURNS BIGINT LANGUAGE sql AS $$
    SELECT user_id FROM users WHERE role = 'recruiter' AND company_id = p_comp
$$;

DROP TABLE IF EXISTS pg_temp.test_results;
CREATE TEMP TABLE test_results (n SERIAL, result TEXT);

DO $$
BEGIN
  -- Tests that must FAIL with a specific error
  INSERT INTO test_results(result) SELECT pg_temp.expect_error('01 overlapping room slot', $q$
    INSERT INTO room_allocations(room_id, round_id, slot_start, slot_end)
    SELECT room_id, round_id, slot_start + interval '5 minutes', slot_end
    FROM room_allocations WHERE allocation_id = 1 $q$,
    '23P01', '%room_allocations_room_time_no_overlap%');

  INSERT INTO test_results(result) SELECT pg_temp.expect_error('02 same candidate twice in one round', $q$
    INSERT INTO queue_entries(candidate_id, allocation_id)
    SELECT 1, a.allocation_id FROM room_allocations a JOIN rounds r ON r.round_id = a.round_id
    WHERE r.company_id = 1 AND r.round_number = 1 AND a.room_id = 2 $q$,
    '23505', 'candidate 1 already has an entry in round%');

  INSERT INTO test_results(result) SELECT pg_temp.expect_error('03 second interview in the same room', $q$
    SELECT change_status(pg_temp.entry(11,1), 'Interviewing', pg_temp.volunteer(1)) $q$,
    '23505', 'room 1 already has an interviewing candidate');

  INSERT INTO test_results(result) SELECT pg_temp.expect_error('04 candidate interviewing in two rooms', $q$
    SELECT change_status(pg_temp.entry(1,2), 'Interviewing', pg_temp.volunteer(6)) $q$,
    '23505', '%one_active_interview_per_candidate%');

  INSERT INTO test_results(result) SELECT pg_temp.expect_error('05 rating outside 1-5', $q$
    INSERT INTO queue_entries(candidate_id, allocation_id, status, rating)
    SELECT 1, a.allocation_id, 'Done', 6 FROM room_allocations a JOIN rounds r ON r.round_id = a.round_id
    WHERE r.company_id = 3 AND r.round_number = 1 AND a.room_id = 1 $q$,
    '23514', '%queue_entries_rating_check%');

  INSERT INTO test_results(result) SELECT pg_temp.expect_error('06 outcome before Done', $q$
    INSERT INTO queue_entries(candidate_id, allocation_id, status, outcome)
    SELECT 1, a.allocation_id, 'In queue', 'Rejected' FROM room_allocations a JOIN rounds r ON r.round_id = a.round_id
    WHERE r.company_id = 3 AND r.round_number = 1 AND a.room_id = 1 $q$,
    '23514', '%outcome_requires_done%');

  INSERT INTO test_results(result) SELECT pg_temp.expect_error('07 invalid status jump', $q$
    SELECT change_status(pg_temp.entry(16,1), 'Done', pg_temp.volunteer(6)) $q$,
    '23514', 'invalid status transition: In queue -> Done');

  INSERT INTO test_results(result) SELECT pg_temp.expect_error('08 recruiter cannot change status', $q$
    SELECT change_status(pg_temp.entry(16,1), 'Interviewing', pg_temp.recruiter(1)) $q$,
    '42501', '%is not authorized to change status');

  INSERT INTO test_results(result) SELECT pg_temp.expect_error('09 stale version', $q$
    SELECT change_status(pg_temp.entry(16,1), 'Interviewing', pg_temp.volunteer(6), 999) $q$,
    '40001', 'stale version: expected 999, actual 1');

  INSERT INTO test_results(result) SELECT pg_temp.expect_error('10 direct update is blocked', $q$
    UPDATE queue_entries SET status = 'Done' WHERE queue_entry_id = pg_temp.entry(16,1) $q$,
    '42501', 'use change_status%');

  INSERT INTO test_results(result) SELECT pg_temp.expect_error('11 volunteer from another room', $q$
    SELECT change_status(pg_temp.entry(16,1), 'Interviewing', pg_temp.volunteer(1)) $q$,
    '42501', '%is not assigned to room%');

  INSERT INTO test_results(result) SELECT pg_temp.expect_error('12 recruiter of another company', $q$
    SELECT change_evaluation(pg_temp.entry(6,1), 4::smallint, 'Shortlisted', pg_temp.recruiter(2)) $q$,
    '42501', '%is not assigned to this company');

  -- Tests that must SUCCEED (run in order)
  INSERT INTO test_results(result) SELECT pg_temp.expect_ok('13 In queue -> Interviewing', $q$
    SELECT change_status(pg_temp.entry(16,1), 'Interviewing', pg_temp.volunteer(6), 1) $q$);

  INSERT INTO test_results(result) SELECT pg_temp.expect_ok('14 Interviewing -> Done', $q$
    SELECT change_status(pg_temp.entry(16,1), 'Done', pg_temp.volunteer(6), 2) $q$);

  INSERT INTO test_results(result) SELECT pg_temp.expect_ok('15 recruiter rates the candidate', $q$
    SELECT change_evaluation(pg_temp.entry(16,1), 5::smallint, 'Shortlisted', pg_temp.recruiter(1), 3) $q$);

  INSERT INTO test_results(result) SELECT pg_temp.expect_ok('16 coordinator undoes Done', $q$
    SELECT change_status(pg_temp.entry(16,1), 'Interviewing',
                         (SELECT user_id FROM users WHERE role = 'coordinator')) $q$);

  INSERT INTO test_results(result) SELECT pg_temp.expect_true('17 history has 5 rows for that entry', $q$
    SELECT count(*) = 5 FROM status_history WHERE queue_entry_id = pg_temp.entry(16,1) $q$);
END $$;

SELECT result FROM test_results ORDER BY n;
