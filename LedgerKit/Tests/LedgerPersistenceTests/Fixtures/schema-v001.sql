CREATE TABLE day_template (
    id TEXT PRIMARY KEY NOT NULL,
    program_id TEXT NOT NULL REFERENCES program(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    name TEXT NOT NULL,
    tag TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);
CREATE TABLE device (
    id TEXT PRIMARY KEY NOT NULL,
    kind TEXT NOT NULL, -- phone or watch
    name TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE TABLE exercise (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    short_name TEXT NOT NULL,
    equipment TEXT NOT NULL,
    primary_muscle TEXT NOT NULL,
    secondary_muscles TEXT NOT NULL, -- JSON array of muscle groups
    pattern TEXT NOT NULL,
    start_load_lb_e7g INTEGER,
    start_load_kg_e7g INTEGER,
    is_custom INTEGER NOT NULL DEFAULT 0,
    curated_alternatives TEXT NOT NULL, -- JSON array of exercise ids
    catalog_version INTEGER,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);
CREATE TABLE logged_set (
    id TEXT PRIMARY KEY NOT NULL,
    workout_exercise_id TEXT NOT NULL REFERENCES workout_exercise(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    weight_e7g INTEGER NOT NULL,
    reps INTEGER NOT NULL,
    kind TEXT NOT NULL,
    done_at REAL,
    e1rm_e7g INTEGER, -- Brzycki, NULL when not done or above 12 reps
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);
CREATE TABLE personal_record ( -- derived from logged_set: local-only, never synced
    id TEXT PRIMARY KEY NOT NULL,
    workout_id TEXT NOT NULL REFERENCES workout(id) ON DELETE CASCADE,
    exercise_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    weight_e7g INTEGER NOT NULL,
    reps INTEGER,
    previous_kind TEXT,
    previous_weight_e7g INTEGER,
    previous_reps INTEGER,
    achieved_at REAL NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);
CREATE TABLE program (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    start_date TEXT NOT NULL,
    goal TEXT,
    days_per_week INTEGER,
    is_active INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);
CREATE TABLE program_week (
    id TEXT PRIMARY KEY NOT NULL,
    program_id TEXT NOT NULL REFERENCES program(id) ON DELETE CASCADE,
    week_index INTEGER NOT NULL,
    is_deload INTEGER NOT NULL DEFAULT 0,
    mon TEXT, -- day_template id, NULL on a rest day
    tue TEXT,
    wed TEXT,
    thu TEXT,
    fri TEXT,
    sat TEXT,
    sun TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);
CREATE TABLE settings (
    id TEXT PRIMARY KEY NOT NULL, -- always 'singleton'
    payload_version INTEGER NOT NULL,
    payload TEXT NOT NULL, -- JSON Settings
    updated_at TEXT NOT NULL
);
CREATE TABLE slot (
    id TEXT PRIMARY KEY NOT NULL,
    day_template_id TEXT NOT NULL REFERENCES day_template(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    exercise_id TEXT NOT NULL REFERENCES exercise(id),
    sets INTEGER NOT NULL,
    reps INTEGER NOT NULL,
    reps_hi INTEGER NOT NULL,
    rpe_x2 INTEGER NOT NULL,
    rest_seconds INTEGER NOT NULL,
    progression TEXT NOT NULL,
    start_load_e7g INTEGER,
    step_e7g INTEGER,
    is_superset_with_previous INTEGER NOT NULL DEFAULT 0,
    drop_sets INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);
CREATE TABLE slot_miss (
    id TEXT PRIMARY KEY NOT NULL,
    slot_id TEXT NOT NULL REFERENCES slot(id) ON DELETE CASCADE,
    week_index INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);
CREATE TABLE workout (
    id TEXT PRIMARY KEY NOT NULL,
    program_id TEXT,
    week_index INTEGER,
    day_template_id TEXT,
    name TEXT NOT NULL,
    tag TEXT NOT NULL,
    is_deload INTEGER NOT NULL DEFAULT 0,
    started_at REAL NOT NULL,
    ended_at REAL,
    phase TEXT NOT NULL,
    units TEXT NOT NULL,
    volume_e7g_reps INTEGER NOT NULL,
    done_sets INTEGER NOT NULL,
    total_sets INTEGER NOT NULL,
    pr_count INTEGER NOT NULL DEFAULT 0,
    origin_device TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);
CREATE TABLE workout_event (
    id INTEGER PRIMARY KEY,
    workout_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    seq INTEGER NOT NULL,
    wall_clock REAL,
    payload_version INTEGER NOT NULL,
    payload BLOB NOT NULL,
    created_at TEXT NOT NULL
);
CREATE TABLE workout_exercise (
    id TEXT PRIMARY KEY NOT NULL,
    workout_id TEXT NOT NULL REFERENCES workout(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    exercise_id TEXT NOT NULL,
    original_exercise_id TEXT NOT NULL,
    slot_id TEXT,
    name TEXT NOT NULL,
    equipment TEXT NOT NULL,
    step_e7g INTEGER NOT NULL,
    rest_seconds INTEGER NOT NULL,
    rpe_x2 INTEGER NOT NULL,
    is_superset_with_previous INTEGER NOT NULL DEFAULT 0,
    target_sets INTEGER NOT NULL,
    target_reps INTEGER NOT NULL,
    target_load_e7g INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);
CREATE TABLE workout_health (
    workout_id TEXT PRIMARY KEY NOT NULL REFERENCES workout(id) ON DELETE CASCADE,
    avg_heart_rate INTEGER,
    max_heart_rate INTEGER,
    active_energy_kcal REAL,
    hk_workout_uuid TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX idx_day_template_program ON day_template(program_id);
CREATE INDEX idx_logged_set_wex ON logged_set(workout_exercise_id);
CREATE INDEX idx_pr_exercise ON personal_record(exercise_id, achieved_at);
CREATE INDEX idx_pr_workout ON personal_record(workout_id);
CREATE INDEX idx_program_week_program ON program_week(program_id);
CREATE INDEX idx_slot_day_template ON slot(day_template_id);
CREATE INDEX idx_slot_exercise ON slot(exercise_id);
CREATE INDEX idx_slot_miss_slot ON slot_miss(slot_id);
CREATE INDEX idx_wex_exercise_workout ON workout_exercise(exercise_id, workout_id);
CREATE INDEX idx_wex_workout ON workout_exercise(workout_id);
CREATE INDEX idx_workout_ended ON workout(ended_at);
CREATE UNIQUE INDEX uidx_event_key ON workout_event(workout_id, device_id, seq);
