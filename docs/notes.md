[
  {
    "result": "PASS  01 overlapping room slot  ->  conflicting key value violates exclusion constraint \"room_allocations_room_time_no_overlap\""
  },
  {
    "result": "PASS  02 same candidate twice in one round  ->  candidate 1 already has an entry in round 1"
  },
  {
    "result": "PASS  03 second interview in the same room  ->  room 1 already has an interviewing candidate"
  },
  {
    "result": "PASS  04 candidate interviewing in two rooms  ->  duplicate key value violates unique constraint \"one_active_interview_per_candidate\""
  },
  {
    "result": "PASS  05 rating outside 1-5  ->  new row for relation \"queue_entries\" violates check constraint \"queue_entries_rating_check\""
  },
  {
    "result": "PASS  06 outcome before Done  ->  new row for relation \"queue_entries\" violates check constraint \"outcome_requires_done\""
  },
  {
    "result": "PASS  07 invalid status jump  ->  invalid status transition: In queue -> Done"
  },
  {
    "result": "PASS  08 recruiter cannot change status  ->  user 2 is not authorized to change status"
  },
  {
    "result": "PASS  09 stale version  ->  stale version: expected 999, actual 1"
  },
  {
    "result": "PASS  10 direct update is blocked  ->  use change_status or change_evaluation to modify audited fields"
  },
  {
    "result": "PASS  11 volunteer from another room  ->  user 7 is not assigned to room 6"
  },
  {
    "result": "PASS  12 recruiter of another company  ->  recruiter 3 is not assigned to this company"
  },
  {
    "result": "PASS  13 In queue -> Interviewing"
  },
  {
    "result": "PASS  14 Interviewing -> Done"
  },
  {
    "result": "PASS  15 recruiter rates the candidate"
  },
  {
    "result": "PASS  16 coordinator undoes Done"
  },
  {
    "result": "PASS  17 history has 5 rows for that entry"
  }
]
