-- seed.sql: fake data only. Run schema.sql first. Safe to re-run.
TRUNCATE status_history, queue_entries, room_allocations, rounds,
         room_volunteers, candidates, users, rooms, companies
RESTART IDENTITY CASCADE;

INSERT INTO companies (company_name) VALUES
('Acme Technologies'), ('Globex Corporation'), ('Initech Systems'),
('Umbrella Digital'), ('Stark Industries');

INSERT INTO rooms (room_name)
SELECT 'Room ' || lpad(n::text, 2, '0') FROM generate_series(1, 10) AS s(n);

INSERT INTO users (full_name, email, role)
VALUES ('Aarav Coordinator', 'coordinator@campus.test', 'coordinator');

INSERT INTO users (full_name, email, role, company_id)
SELECT 'Recruiter ' || c.company_name, 'recruiter' || c.company_id || '@campus.test',
       'recruiter', c.company_id
FROM companies c;

INSERT INTO users (full_name, email, role)
SELECT 'Volunteer ' || lpad(n::text, 2, '0'),
       'volunteer' || lpad(n::text, 2, '0') || '@campus.test', 'room_volunteer'
FROM generate_series(1, 20) AS s(n);

INSERT INTO room_volunteers (room_id, user_id)
SELECT r.room_id, v.user_id
FROM (SELECT room_id, row_number() OVER (ORDER BY room_id) AS rn FROM rooms) r
JOIN (SELECT user_id, row_number() OVER (ORDER BY user_id) AS vn
      FROM users WHERE role = 'room_volunteer') v
  ON v.vn IN (r.rn * 2 - 1, r.rn * 2);

INSERT INTO candidates (full_name, email, phone, college, graduation_year)
SELECT 'Candidate ' || lpad(n::text, 3, '0'),
       'candidate' || lpad(n::text, 3, '0') || '@campus.test',
       '+91-90000-' || lpad(n::text, 5, '0'),
       CASE ((n - 1) % 5)
         WHEN 0 THEN 'North Valley Institute'
         WHEN 1 THEN 'Metro Engineering College'
         WHEN 2 THEN 'Lakeside University'
         WHEN 3 THEN 'Pioneer Institute of Technology'
         ELSE 'National School of Computing' END,
       2026
FROM generate_series(1, 200) AS s(n);

INSERT INTO rounds (company_id, round_number, round_name)
SELECT c.company_id, r.round_number,
       CASE r.round_number WHEN 1 THEN 'Technical screen' ELSE 'Managerial round' END
FROM companies c CROSS JOIN (VALUES (1), (2)) AS r(round_number);

-- Each round gets its own 30-minute slot, so slots never overlap in a room.
INSERT INTO room_allocations (room_id, round_id, slot_start, slot_end)
SELECT rm.room_id, ro.round_id,
       TIMESTAMPTZ '2026-12-01 09:00:00+05:30' + ro.slot_no * interval '30 minutes',
       TIMESTAMPTZ '2026-12-01 09:30:00+05:30' + ro.slot_no * interval '30 minutes'
FROM rooms rm
CROSS JOIN (
    SELECT round_id,
           row_number() OVER (ORDER BY company_id, round_number) - 1 AS slot_no
    FROM rounds
) ro;

-- Company 1, round 1: all 200 candidates. Rating/outcome only when status = Done.
INSERT INTO queue_entries (candidate_id, allocation_id, status, rating, outcome, remark)
SELECT s.candidate_id, s.allocation_id, s.status,
       CASE WHEN s.status = 'Done' THEN ((s.candidate_id - 1) % 5) + 1 END,
       CASE WHEN s.status = 'Done'
            THEN CASE WHEN s.candidate_id % 2 = 0 THEN 'Shortlisted' ELSE 'Rejected' END
       END,
       'Seed record'
FROM (
    SELECT c.candidate_id, a.allocation_id,
           CASE WHEN c.candidate_id BETWEEN 1 AND 5 THEN 'Interviewing'
                WHEN c.candidate_id % 3 = 0 THEN 'Done'
                ELSE 'In queue' END AS status
    FROM candidates c
    JOIN rounds ro ON ro.company_id = 1 AND ro.round_number = 1
    JOIN room_allocations a ON a.round_id = ro.round_id
                           AND a.room_id = ((c.candidate_id - 1) % 10) + 1
) s;

-- Company 2, round 1: candidates 1-40 (multi-company placement).
INSERT INTO queue_entries (candidate_id, allocation_id, status, rating, outcome, remark)
SELECT c.candidate_id, a.allocation_id,
       CASE WHEN c.candidate_id BETWEEN 1 AND 5 THEN 'In queue' ELSE 'Done' END,
       CASE WHEN c.candidate_id BETWEEN 1 AND 5 THEN NULL ELSE ((c.candidate_id + 1) % 5) + 1 END,
       CASE WHEN c.candidate_id BETWEEN 1 AND 5 THEN NULL
            WHEN c.candidate_id % 2 = 0 THEN 'Shortlisted' ELSE 'On hold' END,
       'Second-company seed record'
FROM candidates c
JOIN rounds ro ON ro.company_id = 2 AND ro.round_number = 1
JOIN room_allocations a ON a.round_id = ro.round_id
                       AND a.room_id = ((c.candidate_id + 4) % 10) + 1
WHERE c.candidate_id BETWEEN 1 AND 40;

INSERT INTO status_history (queue_entry_id, changed_by, old_status, new_status,
                            old_rating, new_rating, old_outcome, new_outcome, remark)
SELECT q.queue_entry_id, u.user_id, NULL, q.status, NULL, q.rating, NULL, q.outcome,
       'Initial seed state'
FROM queue_entries q
JOIN users u ON u.email = 'coordinator@campus.test';
