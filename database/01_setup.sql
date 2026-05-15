-- -------------------------------------------------------------
-- 1. РАСШИРЕНИЯ
-- -------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "pgcrypto";    -- crypt(), gen_salt()

-- -------------------------------------------------------------
-- 2. СХЕМЫ
-- -------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS school_core;
CREATE SCHEMA IF NOT EXISTS school_edu;
CREATE SCHEMA IF NOT EXISTS school_fin;
CREATE SCHEMA IF NOT EXISTS school_audit;

-- -------------------------------------------------------------
-- 3. ENUM-ТИПЫ
-- -------------------------------------------------------------

-- Роли пользователей
CREATE TYPE school_core.user_role AS ENUM (
    'admin',
    'teacher',
    'student'
);

-- Тип урока
CREATE TYPE school_edu.lesson_type AS ENUM (
    'webinar',
    'video'
);

-- Тип проверки домашнего задания
CREATE TYPE school_edu.check_type AS ENUM (
    'manual',
    'auto'
);

-- Статус сдачи домашнего задания
CREATE TYPE school_edu.submission_status AS ENUM (
    'submitted',      -- сдано, ожидает проверки
    'checked',        -- проверено преподавателем
    'auto_checked'    -- проверено автоматически
);

-- Тип подписки / оплаты
CREATE TYPE school_fin.subscription_type AS ENUM (
    'monthly',
    'yearly'
);

-- -------------------------------------------------------------
-- 4. ТАБЛИЦЫ
-- -------------------------------------------------------------

-- ==========================
-- СХЕМА: school_core
-- ==========================

-- Пользователи системы (администраторы, преподаватели, студенты)
CREATE TABLE school_core.users (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    email           VARCHAR(255) NOT NULL UNIQUE,
    password_hash   TEXT        NOT NULL,
    role            school_core.user_role NOT NULL,
    first_name      VARCHAR(100) NOT NULL,
    last_name       VARCHAR(100) NOT NULL,
    middle_name     VARCHAR(100),
    phone           VARCHAR(20),
    avatar_url      TEXT,
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  school_core.users              IS 'Все пользователи платформы';
COMMENT ON COLUMN school_core.users.role         IS 'Роль: admin, teacher, student';
COMMENT ON COLUMN school_core.users.password_hash IS 'Хэш пароля (pgcrypto crypt)';

-- ==========================
-- СХЕМА: school_edu
-- ==========================

-- Темы (ЕГЭ, ОГЭ и т.д.)
CREATE TABLE school_edu.topics (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE school_edu.topics IS 'Направления: ЕГЭ, ОГЭ и др.';

-- Курсы
CREATE TABLE school_edu.courses (
    id             UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    topic_id       UUID           NOT NULL REFERENCES school_edu.topics(id) ON DELETE RESTRICT,
    title          VARCHAR(255)   NOT NULL,
    subject        VARCHAR(100)   NOT NULL,
    description    TEXT,
    price_monthly  NUMERIC(10,2)  CHECK (price_monthly >= 0),
    price_yearly   NUMERIC(10,2)  CHECK (price_yearly >= 0),
    is_active      BOOLEAN        NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  school_edu.courses         IS 'Курсы платформы (ЕГЭ по математике и т.д.)';
COMMENT ON COLUMN school_edu.courses.subject IS 'Предмет курса: математика, русский язык и т.д.';

-- Преподаватели курса (M:M users <-> courses)
CREATE TABLE school_edu.course_teachers (
    course_id   UUID        NOT NULL REFERENCES school_edu.courses(id) ON DELETE CASCADE,
    teacher_id  UUID        NOT NULL REFERENCES school_core.users(id)  ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (course_id, teacher_id)
);

COMMENT ON TABLE school_edu.course_teachers IS 'Связь курса с преподавателями (M:M)';

-- Модули курса
CREATE TABLE school_edu.modules (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id   UUID         NOT NULL REFERENCES school_edu.courses(id) ON DELETE CASCADE,
    title       VARCHAR(255) NOT NULL,
    order_index SMALLINT     NOT NULL CHECK (order_index > 0),
    description TEXT,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (course_id, order_index)
);

COMMENT ON TABLE  school_edu.modules             IS 'Модули внутри курса';
COMMENT ON COLUMN school_edu.modules.order_index IS 'Порядковый номер модуля в курсе';

-- Уроки
CREATE TABLE school_edu.lessons (
    id                   UUID                    PRIMARY KEY DEFAULT gen_random_uuid(),
    module_id            UUID                    NOT NULL REFERENCES school_edu.modules(id) ON DELETE CASCADE,
    title                VARCHAR(255)            NOT NULL,
    lesson_type          school_edu.lesson_type  NOT NULL,
    order_index          SMALLINT                NOT NULL CHECK (order_index > 0),
    description          TEXT,
    video_url            TEXT,
    webinar_url          TEXT,
    webinar_scheduled_at TIMESTAMPTZ,
    duration_minutes     SMALLINT                CHECK (duration_minutes > 0),
    is_published         BOOLEAN                 NOT NULL DEFAULT FALSE,
    created_at           TIMESTAMPTZ             NOT NULL DEFAULT NOW(),
    UNIQUE (module_id, order_index),
    -- Для вебинара обязателен URL и дата; для видео — URL видео
    CONSTRAINT chk_webinar_fields CHECK (
        lesson_type <> 'webinar' OR (webinar_url IS NOT NULL AND webinar_scheduled_at IS NOT NULL)
    ),
    CONSTRAINT chk_video_fields CHECK (
        lesson_type <> 'video' OR video_url IS NOT NULL
    )
);

COMMENT ON TABLE  school_edu.lessons                      IS 'Уроки внутри модуля';
COMMENT ON COLUMN school_edu.lessons.lesson_type          IS 'webinar — живой вебинар, video — видео в записи';
COMMENT ON COLUMN school_edu.lessons.webinar_scheduled_at IS 'Дата и время проведения вебинара';

-- Домашние задания
CREATE TABLE school_edu.homeworks (
    id             UUID                   PRIMARY KEY DEFAULT gen_random_uuid(),
    lesson_id      UUID                   NOT NULL REFERENCES school_edu.lessons(id) ON DELETE CASCADE,
    title          VARCHAR(255)           NOT NULL,
    description    TEXT,
    check_type     school_edu.check_type  NOT NULL,
    max_score      SMALLINT               NOT NULL CHECK (max_score > 0),
    deadline_hours SMALLINT               CHECK (deadline_hours > 0),
    created_at     TIMESTAMPTZ            NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  school_edu.homeworks            IS 'Домашние задания к урокам';
COMMENT ON COLUMN school_edu.homeworks.check_type IS 'manual — проверяет преподаватель, auto — автоматически';
COMMENT ON COLUMN school_edu.homeworks.max_score  IS 'Максимально возможный балл';

-- Сдачи домашних заданий студентами
CREATE TABLE school_edu.homework_submissions (
    id           UUID                        PRIMARY KEY DEFAULT gen_random_uuid(),
    homework_id  UUID                        NOT NULL REFERENCES school_edu.homeworks(id) ON DELETE CASCADE,
    student_id   UUID                        NOT NULL REFERENCES school_core.users(id)    ON DELETE CASCADE,
    answer_text  TEXT,
    answer_url   TEXT,
    score        SMALLINT                    CHECK (score >= 0),
    status       school_edu.submission_status NOT NULL DEFAULT 'submitted',
    checked_by   UUID                        REFERENCES school_core.users(id),
    checked_at   TIMESTAMPTZ,
    submitted_at TIMESTAMPTZ                 NOT NULL DEFAULT NOW(),
    -- Одна сдача на студента (пересдача запрещена)
    UNIQUE (homework_id, student_id),
    -- Балл не может превышать максимальный (проверяется триггером)
    CONSTRAINT chk_answer_provided CHECK (
        answer_text IS NOT NULL OR answer_url IS NOT NULL
    )
);

COMMENT ON TABLE  school_edu.homework_submissions          IS 'Сдача ДЗ студентом';
COMMENT ON COLUMN school_edu.homework_submissions.score    IS 'Выставленный балл (NULL пока не проверено)';
COMMENT ON COLUMN school_edu.homework_submissions.status   IS 'submitted / checked / auto_checked';

-- Зачисления студентов на курсы
CREATE TABLE school_edu.enrollments (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id  UUID        NOT NULL REFERENCES school_core.users(id)  ON DELETE CASCADE,
    course_id   UUID        NOT NULL REFERENCES school_edu.courses(id) ON DELETE RESTRICT,
    enrolled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
    UNIQUE (student_id, course_id)
);

COMMENT ON TABLE school_edu.enrollments IS 'Зачисление студента на курс администратором';

-- Прогресс студента по урокам
CREATE TABLE school_edu.lesson_progress (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id     UUID        NOT NULL REFERENCES school_core.users(id)   ON DELETE CASCADE,
    lesson_id      UUID        NOT NULL REFERENCES school_edu.lessons(id)  ON DELETE CASCADE,
    is_completed   BOOLEAN     NOT NULL DEFAULT FALSE,
    completed_at   TIMESTAMPTZ,
    last_viewed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (student_id, lesson_id)
);

COMMENT ON TABLE school_edu.lesson_progress IS 'Отслеживание прогресса студента по урокам';

-- Лог активности пользователей
CREATE TABLE school_audit.activity_log (
    id          BIGSERIAL    PRIMARY KEY,
    user_id     UUID         NOT NULL REFERENCES school_core.users(id) ON DELETE CASCADE,
    action      VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50),
    entity_id   UUID,
    metadata    JSONB,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  school_audit.activity_log             IS 'Лог действий пользователей';
COMMENT ON COLUMN school_audit.activity_log.action      IS 'login, view_lesson, submit_hw, enroll и т.д.';
COMMENT ON COLUMN school_audit.activity_log.entity_type IS 'Тип сущности: lesson, homework, course';
COMMENT ON COLUMN school_audit.activity_log.metadata    IS 'Произвольные доп. данные в JSON';

-- ==========================
-- СХЕМА: school_fin
-- ==========================

-- Платежи
CREATE TABLE school_fin.payments (
    id                UUID                       PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id        UUID                       NOT NULL REFERENCES school_core.users(id)  ON DELETE RESTRICT,
    course_id         UUID                       NOT NULL REFERENCES school_edu.courses(id) ON DELETE RESTRICT,
    amount            NUMERIC(10,2)              NOT NULL CHECK (amount > 0),
    subscription_type school_fin.subscription_type NOT NULL,
    payment_date      DATE                       NOT NULL DEFAULT CURRENT_DATE,
    period_start      DATE                       NOT NULL,
    period_end        DATE                       NOT NULL,
    notes             TEXT,
    created_by        UUID                       NOT NULL REFERENCES school_core.users(id),
    created_at        TIMESTAMPTZ                NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_period CHECK (period_end > period_start)
);

COMMENT ON TABLE  school_fin.payments                  IS 'Фиксация оплат студентов за курсы';
COMMENT ON COLUMN school_fin.payments.subscription_type IS 'monthly — ежемесячная, yearly — годовая';
COMMENT ON COLUMN school_fin.payments.created_by        IS 'Администратор, зафиксировавший оплату';

-- -------------------------------------------------------------
-- 5. ИНДЕКСЫ
-- -------------------------------------------------------------

-- users
CREATE INDEX idx_users_role       ON school_core.users(role);
CREATE INDEX idx_users_email      ON school_core.users(email);
CREATE INDEX idx_users_is_active  ON school_core.users(is_active);

-- courses
CREATE INDEX idx_courses_topic_id  ON school_edu.courses(topic_id);
CREATE INDEX idx_courses_is_active ON school_edu.courses(is_active);

-- course_teachers
CREATE INDEX idx_course_teachers_teacher ON school_edu.course_teachers(teacher_id);

-- modules
CREATE INDEX idx_modules_course_id ON school_edu.modules(course_id);

-- lessons
CREATE INDEX idx_lessons_module_id   ON school_edu.lessons(module_id);
CREATE INDEX idx_lessons_type        ON school_edu.lessons(lesson_type);
CREATE INDEX idx_lessons_published   ON school_edu.lessons(is_published);
CREATE INDEX idx_lessons_webinar_dt  ON school_edu.lessons(webinar_scheduled_at)
    WHERE lesson_type = 'webinar';

-- homeworks
CREATE INDEX idx_homeworks_lesson_id ON school_edu.homeworks(lesson_id);

-- homework_submissions
CREATE INDEX idx_hw_sub_homework_id  ON school_edu.homework_submissions(homework_id);
CREATE INDEX idx_hw_sub_student_id   ON school_edu.homework_submissions(student_id);
CREATE INDEX idx_hw_sub_status       ON school_edu.homework_submissions(status);

-- enrollments
CREATE INDEX idx_enrollments_student  ON school_edu.enrollments(student_id);
CREATE INDEX idx_enrollments_course   ON school_edu.enrollments(course_id);
CREATE INDEX idx_enrollments_active   ON school_edu.enrollments(is_active);

-- lesson_progress
CREATE INDEX idx_lp_student_id  ON school_edu.lesson_progress(student_id);
CREATE INDEX idx_lp_lesson_id   ON school_edu.lesson_progress(lesson_id);
CREATE INDEX idx_lp_completed   ON school_edu.lesson_progress(is_completed);

-- activity_log
CREATE INDEX idx_activity_user_id    ON school_audit.activity_log(user_id);
CREATE INDEX idx_activity_action     ON school_audit.activity_log(action);
CREATE INDEX idx_activity_created_at ON school_audit.activity_log(created_at DESC);
CREATE INDEX idx_activity_entity     ON school_audit.activity_log(entity_type, entity_id);

-- payments
CREATE INDEX idx_payments_student_id   ON school_fin.payments(student_id);
CREATE INDEX idx_payments_course_id    ON school_fin.payments(course_id);
CREATE INDEX idx_payments_date         ON school_fin.payments(payment_date DESC);
CREATE INDEX idx_payments_sub_type     ON school_fin.payments(subscription_type);

-- =============================================================
-- ОНЛАЙН-ШКОЛА: Шаг 2 — Views и Materialized Views
-- =============================================================
-- Список представлений:
--
--  ОБЫЧНЫЕ VIEWS (актуальные данные в реальном времени):
--  1.  v_active_students          — активные студенты с кол-вом курсов
--  2.  v_teachers_courses         — преподаватели и их курсы
--  3.  v_upcoming_webinars        — ближайшие вебинары
--  4.  v_pending_homeworks        — ДЗ, ожидающие проверки преподавателем
--  5.  v_student_progress         — прогресс каждого студента по каждому курсу
--  6.  v_course_finance           — финансы по каждому курсу
--
--  MATERIALIZED VIEWS (для дашборда администратора — быстрые):
--  7.  mv_admin_dashboard         — сводная статистика платформы
--  8.  mv_student_scores          — рейтинг студентов по баллам
--  9.  mv_course_completion       — % завершения курсов
--  10. mv_teacher_workload        — загруженность преподавателей
-- =============================================================


-- =============================================================
-- ОБЫЧНЫЕ VIEWS
-- =============================================================

-- -------------------------------------------------------------
-- 1. v_active_students
--    Все активные студенты с количеством записанных курсов
--    и датой последней активности
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW school_edu.v_active_students AS
SELECT
    u.id                                        AS student_id,
    u.last_name || ' ' || u.first_name
        || COALESCE(' ' || u.middle_name, '')   AS full_name,
    u.email,
    u.phone,
    u.created_at                                AS registered_at,
    COUNT(DISTINCT e.course_id)
        FILTER (WHERE e.is_active = TRUE)       AS active_courses_count,
    MAX(al.created_at)                          AS last_activity_at
FROM school_core.users u
LEFT JOIN school_edu.enrollments       e  ON e.student_id = u.id
LEFT JOIN school_audit.activity_log    al ON al.user_id   = u.id
WHERE u.role      = 'student'
  AND u.is_active = TRUE
GROUP BY u.id, u.last_name, u.first_name, u.middle_name,
         u.email, u.phone, u.created_at;

COMMENT ON VIEW school_edu.v_active_students IS
    'Активные студенты: количество курсов и дата последней активности';


-- -------------------------------------------------------------
-- 2. v_teachers_courses
--    Преподаватели со списком своих курсов
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW school_edu.v_teachers_courses AS
SELECT
    u.id                                        AS teacher_id,
    u.last_name || ' ' || u.first_name
        || COALESCE(' ' || u.middle_name, '')   AS full_name,
    u.email,
    t.name                                      AS topic_name,
    c.id                                        AS course_id,
    c.title                                     AS course_title,
    c.subject,
    c.is_active                                 AS course_is_active,
    COUNT(DISTINCT e.student_id)
        FILTER (WHERE e.is_active = TRUE)       AS enrolled_students_count,
    ct.assigned_at
FROM school_core.users          u
JOIN school_edu.course_teachers  ct ON ct.teacher_id = u.id
JOIN school_edu.courses          c  ON c.id          = ct.course_id
JOIN school_edu.topics           t  ON t.id          = c.topic_id
LEFT JOIN school_edu.enrollments e  ON e.course_id   = c.id
WHERE u.role = 'teacher'
GROUP BY u.id, u.last_name, u.first_name, u.middle_name,
         u.email, t.name, c.id, c.title, c.subject,
         c.is_active, ct.assigned_at;

COMMENT ON VIEW school_edu.v_teachers_courses IS
    'Преподаватели с курсами и количеством зачисленных студентов';


-- -------------------------------------------------------------
-- 3. v_upcoming_webinars
--    Вебинары, запланированные в будущем (следующие 30 дней)
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW school_edu.v_upcoming_webinars AS
SELECT
    l.id                        AS lesson_id,
    l.title                     AS lesson_title,
    l.webinar_scheduled_at,
    l.webinar_url,
    l.duration_minutes,
    m.title                     AS module_title,
    c.id                        AS course_id,
    c.title                     AS course_title,
    c.subject,
    t.name                      AS topic_name,
    -- Сколько студентов записано на этот курс
    COUNT(DISTINCT e.student_id)
        FILTER (WHERE e.is_active = TRUE) AS enrolled_count,
    -- Список преподавателей через запятую
    STRING_AGG(
        DISTINCT u.last_name || ' ' || u.first_name,
        ', ' ORDER BY u.last_name || ' ' || u.first_name
    )                           AS teachers
FROM school_edu.lessons          l
JOIN school_edu.modules          m  ON m.id         = l.module_id
JOIN school_edu.courses          c  ON c.id         = m.course_id
JOIN school_edu.topics           t  ON t.id         = c.topic_id
LEFT JOIN school_edu.enrollments  e  ON e.course_id  = c.id
LEFT JOIN school_edu.course_teachers ct ON ct.course_id = c.id
LEFT JOIN school_core.users       u  ON u.id         = ct.teacher_id
WHERE l.lesson_type          = 'webinar'
  AND l.is_published         = TRUE
  AND l.webinar_scheduled_at BETWEEN NOW() AND NOW() + INTERVAL '30 days'
GROUP BY l.id, l.title, l.webinar_scheduled_at, l.webinar_url,
         l.duration_minutes, m.title, c.id, c.title,
         c.subject, t.name
ORDER BY l.webinar_scheduled_at;

COMMENT ON VIEW school_edu.v_upcoming_webinars IS
    'Ближайшие вебинары на 30 дней вперёд';


-- -------------------------------------------------------------
-- 4. v_pending_homeworks
--    ДЗ, ожидающие ручной проверки преподавателем.
--    Преподаватель видит только студентов своих курсов.
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW school_edu.v_pending_homeworks AS
SELECT
    hs.id                                           AS submission_id,
    hs.submitted_at,
    -- Студент
    hs.student_id,
    u_st.last_name || ' ' || u_st.first_name        AS student_name,
    -- ДЗ
    hw.id                                           AS homework_id,
    hw.title                                        AS homework_title,
    hw.max_score,
    -- Урок / модуль / курс
    l.id                                            AS lesson_id,
    l.title                                         AS lesson_title,
    m.title                                         AS module_title,
    c.id                                            AS course_id,
    c.title                                         AS course_title,
    -- Преподаватели курса (для фильтрации на уровне приложения)
    ARRAY_AGG(DISTINCT ct.teacher_id)               AS teacher_ids,
    hs.answer_text,
    hs.answer_url
FROM school_edu.homework_submissions  hs
JOIN school_edu.homeworks             hw ON hw.id        = hs.homework_id
JOIN school_edu.lessons               l  ON l.id         = hw.lesson_id
JOIN school_edu.modules               m  ON m.id         = l.module_id
JOIN school_edu.courses               c  ON c.id         = m.course_id
JOIN school_core.users                u_st ON u_st.id    = hs.student_id
LEFT JOIN school_edu.course_teachers  ct ON ct.course_id = c.id
WHERE hs.status    = 'submitted'
  AND hw.check_type = 'manual'
GROUP BY hs.id, hs.submitted_at, hs.student_id,
         u_st.last_name, u_st.first_name,
         hw.id, hw.title, hw.max_score,
         l.id, l.title, m.title,
         c.id, c.title,
         hs.answer_text, hs.answer_url
ORDER BY hs.submitted_at;

COMMENT ON VIEW school_edu.v_pending_homeworks IS
    'ДЗ с ручной проверкой, ожидающие проверки. teacher_ids для фильтрации по преподавателю.';


-- -------------------------------------------------------------
-- 5. v_student_progress
--    Детальный прогресс каждого студента по каждому курсу:
--    просмотрено уроков, выполнено ДЗ, набранные баллы
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW school_edu.v_student_progress AS
WITH
-- Общее количество уроков в курсе
course_lessons AS (
    SELECT
        m.course_id,
        COUNT(l.id) AS total_lessons
    FROM school_edu.modules m
    JOIN school_edu.lessons  l ON l.module_id = m.id
    WHERE l.is_published = TRUE
    GROUP BY m.course_id
),
-- Количество уроков, которые студент завершил
student_completed AS (
    SELECT
        e.student_id,
        e.course_id,
        COUNT(lp.id) AS completed_lessons
    FROM school_edu.enrollments    e
    JOIN school_edu.modules        m  ON m.course_id  = e.course_id
    JOIN school_edu.lessons        l  ON l.module_id  = m.id
    LEFT JOIN school_edu.lesson_progress lp
        ON lp.lesson_id  = l.id
       AND lp.student_id = e.student_id
       AND lp.is_completed = TRUE
    WHERE l.is_published = TRUE
    GROUP BY e.student_id, e.course_id
),
-- Статистика по ДЗ для студента в курсе
student_hw AS (
    SELECT
        e.student_id,
        e.course_id,
        COUNT(hw.id)                                        AS total_homeworks,
        COUNT(hs.id)                                        AS submitted_homeworks,
        COALESCE(SUM(hs.score), 0)                          AS total_score,
        COALESCE(SUM(hw.max_score), 0)                      AS max_possible_score
    FROM school_edu.enrollments  e
    JOIN school_edu.modules      m   ON m.course_id   = e.course_id
    JOIN school_edu.lessons      l   ON l.module_id   = m.id
    JOIN school_edu.homeworks    hw  ON hw.lesson_id  = l.id
    LEFT JOIN school_edu.homework_submissions hs
        ON hs.homework_id = hw.id
       AND hs.student_id  = e.student_id
       AND hs.status IN ('checked', 'auto_checked')
    WHERE l.is_published = TRUE
    GROUP BY e.student_id, e.course_id
)
SELECT
    u.id                                                AS student_id,
    u.last_name || ' ' || u.first_name                  AS student_name,
    u.email,
    c.id                                                AS course_id,
    c.title                                             AS course_title,
    c.subject,
    t.name                                              AS topic_name,
    e.enrolled_at,
    e.is_active                                         AS enrollment_active,
    -- Прогресс по урокам
    COALESCE(cl.total_lessons, 0)                       AS total_lessons,
    COALESCE(sc.completed_lessons, 0)                   AS completed_lessons,
    CASE
        WHEN COALESCE(cl.total_lessons, 0) = 0 THEN 0
        ELSE ROUND(
            sc.completed_lessons::NUMERIC / cl.total_lessons * 100, 1
        )
    END                                                 AS lessons_progress_pct,
    -- Прогресс по ДЗ
    COALESCE(sh.total_homeworks, 0)                     AS total_homeworks,
    COALESCE(sh.submitted_homeworks, 0)                 AS submitted_homeworks,
    COALESCE(sh.total_score, 0)                         AS total_score,
    COALESCE(sh.max_possible_score, 0)                  AS max_possible_score,
    CASE
        WHEN COALESCE(sh.max_possible_score, 0) = 0 THEN 0
        ELSE ROUND(
            sh.total_score::NUMERIC / sh.max_possible_score * 100, 1
        )
    END                                                 AS score_pct
FROM school_edu.enrollments     e
JOIN school_core.users           u  ON u.id         = e.student_id
JOIN school_edu.courses          c  ON c.id         = e.course_id
JOIN school_edu.topics           t  ON t.id         = c.topic_id
LEFT JOIN course_lessons         cl ON cl.course_id  = e.course_id
LEFT JOIN student_completed      sc ON sc.student_id = e.student_id
                                    AND sc.course_id  = e.course_id
LEFT JOIN student_hw             sh ON sh.student_id = e.student_id
                                    AND sh.course_id  = e.course_id;

COMMENT ON VIEW school_edu.v_student_progress IS
    'Полный прогресс студента по курсу: уроки, ДЗ, баллы, процент завершения';


-- -------------------------------------------------------------
-- 6. v_course_finance
--    Финансовая сводка по каждому курсу
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW school_fin.v_course_finance AS
SELECT
    c.id                                            AS course_id,
    c.title                                         AS course_title,
    c.subject,
    t.name                                          AS topic_name,
    -- Всего поступлений
    COALESCE(SUM(p.amount), 0)                      AS total_revenue,
    -- По типу подписки
    COALESCE(SUM(p.amount)
        FILTER (WHERE p.subscription_type = 'monthly'), 0) AS revenue_monthly,
    COALESCE(SUM(p.amount)
        FILTER (WHERE p.subscription_type = 'yearly'),  0) AS revenue_yearly,
    -- Количество платежей
    COUNT(p.id)                                     AS payments_count,
    COUNT(DISTINCT p.student_id)                    AS paying_students_count,
    -- Даты
    MIN(p.payment_date)                             AS first_payment_date,
    MAX(p.payment_date)                             AS last_payment_date
FROM school_edu.courses     c
JOIN school_edu.topics      t ON t.id       = c.topic_id
LEFT JOIN school_fin.payments p ON p.course_id = c.id
GROUP BY c.id, c.title, c.subject, t.name;

COMMENT ON VIEW school_fin.v_course_finance IS
    'Финансовая сводка по каждому курсу';


-- =============================================================
-- MATERIALIZED VIEWS (для панели администратора)
-- =============================================================

-- -------------------------------------------------------------
-- 7. mv_admin_dashboard
--    Главная сводка платформы для дашборда администратора
-- -------------------------------------------------------------
CREATE MATERIALIZED VIEW school_audit.mv_admin_dashboard AS
SELECT
    1                                               AS id,  -- суррогатный ключ для REFRESH CONCURRENTLY
    -- Пользователи
    (SELECT COUNT(*) FROM school_core.users WHERE role = 'student' AND is_active = TRUE)
                                                AS total_active_students,
    (SELECT COUNT(*) FROM school_core.users WHERE role = 'teacher' AND is_active = TRUE)
                                                AS total_active_teachers,
    -- Курсы
    (SELECT COUNT(*) FROM school_edu.courses WHERE is_active = TRUE)
                                                AS total_active_courses,
    -- Зачисления
    (SELECT COUNT(*) FROM school_edu.enrollments WHERE is_active = TRUE)
                                                AS total_active_enrollments,
    -- ДЗ
    (SELECT COUNT(*) FROM school_edu.homework_submissions WHERE status = 'submitted')
                                                AS pending_hw_checks,
    (SELECT COUNT(*) FROM school_edu.homework_submissions)
                                                AS total_submissions,
    -- Финансы: текущий месяц
    (SELECT COALESCE(SUM(amount), 0)
     FROM school_fin.payments
     WHERE DATE_TRUNC('month', payment_date) = DATE_TRUNC('month', CURRENT_DATE))
                                                AS revenue_current_month,
    -- Финансы: текущий год
    (SELECT COALESCE(SUM(amount), 0)
     FROM school_fin.payments
     WHERE DATE_TRUNC('year', payment_date) = DATE_TRUNC('year', CURRENT_DATE))
                                                AS revenue_current_year,
    -- Финансы: всего за всё время
    (SELECT COALESCE(SUM(amount), 0) FROM school_fin.payments)
                                                AS revenue_total,
    -- Активность: пользователи за последние 7 дней
    (SELECT COUNT(DISTINCT user_id)
     FROM school_audit.activity_log
     WHERE created_at >= NOW() - INTERVAL '7 days')
                                                AS active_users_last_7days,
    -- Ближайший вебинар
    (SELECT webinar_scheduled_at
     FROM school_edu.lessons
     WHERE lesson_type = 'webinar'
       AND is_published = TRUE
       AND webinar_scheduled_at > NOW()
     ORDER BY webinar_scheduled_at
     LIMIT 1)                                   AS next_webinar_at,
    NOW()                                       AS refreshed_at
WITH DATA;

CREATE UNIQUE INDEX idx_mv_admin_dashboard_id
    ON school_audit.mv_admin_dashboard(id);

COMMENT ON MATERIALIZED VIEW school_audit.mv_admin_dashboard IS
    'Сводная статистика платформы для панели администратора. Обновлять через REFRESH.';


-- -------------------------------------------------------------
-- 8. mv_student_scores
--    Рейтинг студентов по суммарным баллам за ДЗ
-- -------------------------------------------------------------
CREATE MATERIALIZED VIEW school_audit.mv_student_scores AS
SELECT
    u.id                                            AS student_id,
    u.last_name || ' ' || u.first_name
        || COALESCE(' ' || u.middle_name, '')        AS full_name,
    u.email,
    c.id                                            AS course_id,
    c.title                                         AS course_title,
    c.subject,
    t.name                                          AS topic_name,
    -- Баллы
    COALESCE(SUM(hs.score), 0)                      AS total_score,
    COALESCE(SUM(hw.max_score), 0)                  AS max_possible_score,
    CASE
        WHEN COALESCE(SUM(hw.max_score), 0) = 0 THEN 0
        ELSE ROUND(SUM(hs.score)::NUMERIC / SUM(hw.max_score) * 100, 1)
    END                                             AS score_pct,
    -- Количество выполненных ДЗ
    COUNT(hs.id)                                    AS completed_hw_count,
    COUNT(hw.id)                                    AS total_hw_count,
    -- Оконная функция: место в рейтинге по курсу
    RANK() OVER (
        PARTITION BY c.id
        ORDER BY COALESCE(SUM(hs.score), 0) DESC
    )                                               AS rank_in_course,
    NOW()                                           AS refreshed_at
FROM school_edu.enrollments          e
JOIN school_core.users               u   ON u.id          = e.student_id
JOIN school_edu.courses              c   ON c.id          = e.course_id
JOIN school_edu.topics               t   ON t.id          = c.topic_id
JOIN school_edu.modules              m   ON m.course_id   = c.id
JOIN school_edu.lessons              l   ON l.module_id   = m.id
JOIN school_edu.homeworks            hw  ON hw.lesson_id  = l.id
LEFT JOIN school_edu.homework_submissions hs
    ON hs.homework_id = hw.id
   AND hs.student_id  = e.student_id
   AND hs.status IN ('checked', 'auto_checked')
WHERE e.is_active    = TRUE
  AND l.is_published = TRUE
GROUP BY u.id, u.last_name, u.first_name, u.middle_name,
         u.email, c.id, c.title, c.subject, t.name
WITH DATA;

CREATE UNIQUE INDEX idx_mv_scores_unique
    ON school_audit.mv_student_scores(student_id, course_id);
CREATE INDEX idx_mv_scores_course   ON school_audit.mv_student_scores(course_id);
CREATE INDEX idx_mv_scores_student  ON school_audit.mv_student_scores(student_id);
CREATE INDEX idx_mv_scores_rank     ON school_audit.mv_student_scores(course_id, rank_in_course);

COMMENT ON MATERIALIZED VIEW school_audit.mv_student_scores IS
    'Рейтинг студентов по баллам с местом в курсе. Обновлять через REFRESH.';


-- -------------------------------------------------------------
-- 9. mv_course_completion
--    Процент завершения курсов по студентам (для дашборда)
-- -------------------------------------------------------------
CREATE MATERIALIZED VIEW school_audit.mv_course_completion AS
WITH total_lessons AS (
    SELECT m.course_id, COUNT(l.id) AS cnt
    FROM school_edu.modules m
    JOIN school_edu.lessons  l ON l.module_id   = m.id
    WHERE l.is_published = TRUE
    GROUP BY m.course_id
),
completed_lessons AS (
    SELECT
        e.student_id,
        e.course_id,
        COUNT(lp.id) AS cnt
    FROM school_edu.enrollments       e
    JOIN school_edu.modules           m  ON m.course_id  = e.course_id
    JOIN school_edu.lessons           l  ON l.module_id  = m.id
    LEFT JOIN school_edu.lesson_progress lp
        ON lp.lesson_id   = l.id
       AND lp.student_id  = e.student_id
       AND lp.is_completed = TRUE
    WHERE l.is_published = TRUE
    GROUP BY e.student_id, e.course_id
)
SELECT
    e.student_id,
    e.course_id,
    c.title                                             AS course_title,
    c.subject,
    t.name                                              AS topic_name,
    COALESCE(tl.cnt, 0)                                 AS total_lessons,
    COALESCE(cl.cnt, 0)                                 AS completed_lessons,
    CASE
        WHEN COALESCE(tl.cnt, 0) = 0 THEN 0
        ELSE ROUND(cl.cnt::NUMERIC / tl.cnt * 100, 1)
    END                                                 AS completion_pct,
    -- Средний процент по курсу (по всем студентам)
    ROUND(AVG(
        CASE WHEN COALESCE(tl.cnt, 0) = 0 THEN 0
             ELSE cl.cnt::NUMERIC / tl.cnt * 100
        END
    ) OVER (PARTITION BY e.course_id), 1)               AS avg_completion_pct_in_course,
    NOW()                                               AS refreshed_at
FROM school_edu.enrollments      e
JOIN school_edu.courses          c  ON c.id          = e.course_id
JOIN school_edu.topics           t  ON t.id          = c.topic_id
LEFT JOIN total_lessons          tl ON tl.course_id  = e.course_id
LEFT JOIN completed_lessons      cl ON cl.student_id = e.student_id
                                    AND cl.course_id  = e.course_id
WHERE e.is_active = TRUE
WITH DATA;

CREATE UNIQUE INDEX idx_mv_completion_unique
    ON school_audit.mv_course_completion(student_id, course_id);
CREATE INDEX idx_mv_completion_course  ON school_audit.mv_course_completion(course_id);
CREATE INDEX idx_mv_completion_student ON school_audit.mv_course_completion(student_id);
CREATE INDEX idx_mv_completion_pct     ON school_audit.mv_course_completion(completion_pct DESC);

COMMENT ON MATERIALIZED VIEW school_audit.mv_course_completion IS
    'Процент завершения курсов по каждому студенту со средним по курсу.';


-- -------------------------------------------------------------
-- 10. mv_teacher_workload
--     Загруженность преподавателей:
--     курсы, студенты, непроверенные ДЗ
-- -------------------------------------------------------------
CREATE MATERIALIZED VIEW school_audit.mv_teacher_workload AS
SELECT
    u.id                                            AS teacher_id,
    u.last_name || ' ' || u.first_name
        || COALESCE(' ' || u.middle_name, '')        AS full_name,
    u.email,
    -- Количество курсов
    COUNT(DISTINCT ct.course_id)                    AS courses_count,
    -- Количество активных студентов по всем курсам
    COUNT(DISTINCT e.student_id)
        FILTER (WHERE e.is_active = TRUE)            AS total_students,
    -- Количество ДЗ, ожидающих проверки
    COUNT(DISTINCT hs.id)
        FILTER (WHERE hs.status = 'submitted')       AS pending_checks,
    -- Количество уже проверенных ДЗ за всё время
    COUNT(DISTINCT hs.id)
        FILTER (WHERE hs.checked_by = u.id)          AS total_checked,
    NOW()                                           AS refreshed_at
FROM school_core.users               u
JOIN school_edu.course_teachers      ct  ON ct.teacher_id  = u.id
JOIN school_edu.courses              c   ON c.id           = ct.course_id
LEFT JOIN school_edu.enrollments     e   ON e.course_id    = c.id
LEFT JOIN school_edu.modules         m   ON m.course_id    = c.id
LEFT JOIN school_edu.lessons         l   ON l.module_id    = m.id
LEFT JOIN school_edu.homeworks       hw  ON hw.lesson_id   = l.id
                                        AND hw.check_type  = 'manual'
LEFT JOIN school_edu.homework_submissions hs
    ON hs.homework_id = hw.id
WHERE u.role      = 'teacher'
  AND u.is_active = TRUE
GROUP BY u.id, u.last_name, u.first_name, u.middle_name, u.email
WITH DATA;

CREATE UNIQUE INDEX idx_mv_workload_teacher ON school_audit.mv_teacher_workload(teacher_id);

COMMENT ON MATERIALIZED VIEW school_audit.mv_teacher_workload IS
    'Загруженность преподавателей: курсы, студенты, непроверенные ДЗ.';


-- =============================================================
-- ФУНКЦИЯ ОБНОВЛЕНИЯ ВСЕХ MATERIALIZED VIEWS
-- Вызывать по расписанию (например, через pg_cron каждый час)
-- =============================================================
CREATE OR REPLACE FUNCTION school_audit.refresh_all_materialized_views()
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY school_audit.mv_admin_dashboard;
    REFRESH MATERIALIZED VIEW CONCURRENTLY school_audit.mv_student_scores;
    REFRESH MATERIALIZED VIEW CONCURRENTLY school_audit.mv_course_completion;
    REFRESH MATERIALIZED VIEW CONCURRENTLY school_audit.mv_teacher_workload;
END;
$$;

COMMENT ON FUNCTION school_audit.refresh_all_materialized_views IS
    'Обновляет все материализованные представления. Запускать по расписанию.';

-- =============================================================
-- ОНЛАЙН-ШКОЛА: Шаг 3 — Хранимые функции (FUNCTIONS)
-- =============================================================
-- Список функций:
--
--  1.  fn_get_user_full_name          — полное имя пользователя
--  2.  fn_get_course_stats            — статистика по одному курсу
--  3.  fn_get_student_rank            — место студента в рейтинге курса
--  4.  fn_calc_period_end             — расчёт даты окончания периода оплаты
--  5.  fn_is_student_enrolled         — проверка зачисления студента
--  6.  fn_get_teacher_students        — студенты преподавателя (TABLE)
--  7.  fn_get_monthly_revenue         — доходы по месяцам за период
--  8.  fn_get_course_progress_report  — отчёт по курсу с CURSOR
--  9.  fn_validate_submission_score   — валидация балла ДЗ (для триггера)
--  10. fn_auto_check_homework         — автопроверка ДЗ (для триггера)
--  11. fn_update_updated_at           — обновление updated_at (для триггера)
-- =============================================================


-- =============================================================
-- 1. fn_get_user_full_name
--    Возвращает полное имя пользователя по его id
--    Используется в других функциях и запросах
-- =============================================================
CREATE OR REPLACE FUNCTION school_core.fn_get_user_full_name(
    p_user_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE                          -- не меняет данные, результат стабилен в транзакции
AS $$
DECLARE
    v_full_name TEXT;
BEGIN
    SELECT
        last_name || ' ' || first_name
        || COALESCE(' ' || middle_name, '')
    INTO v_full_name
    FROM school_core.users
    WHERE id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Пользователь с id=% не найден', p_user_id;
    END IF;

    RETURN TRIM(v_full_name);
END;
$$;

COMMENT ON FUNCTION school_core.fn_get_user_full_name(UUID) IS
    'Возвращает полное имя (фамилия имя отчество) пользователя по UUID';


-- =============================================================
-- 2. fn_get_course_stats
--    Возвращает сводную статистику по одному курсу:
--    количество модулей, уроков, ДЗ, студентов, выручку
-- =============================================================
CREATE OR REPLACE FUNCTION school_edu.fn_get_course_stats(
    p_course_id UUID
)
RETURNS TABLE (
    course_id           UUID,
    course_title        TEXT,
    topic_name          TEXT,
    subject             TEXT,
    modules_count       BIGINT,
    lessons_count       BIGINT,
    webinars_count      BIGINT,
    videos_count        BIGINT,
    homeworks_count     BIGINT,
    enrolled_students   BIGINT,
    total_revenue       NUMERIC,
    avg_completion_pct  NUMERIC
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.id,
        c.title::TEXT,
        t.name::TEXT,
        c.subject::TEXT,
        COUNT(DISTINCT m.id),
        COUNT(DISTINCT l.id),
        COUNT(DISTINCT l.id) FILTER (WHERE l.lesson_type = 'webinar'),
        COUNT(DISTINCT l.id) FILTER (WHERE l.lesson_type = 'video'),
        COUNT(DISTINCT hw.id),
        COUNT(DISTINCT e.student_id) FILTER (WHERE e.is_active = TRUE),
        COALESCE(SUM(DISTINCT p.amount), 0),
        COALESCE(
            ROUND(AVG(mcc.completion_pct), 1),
            0
        )
    FROM school_edu.courses                  c
    JOIN school_edu.topics                   t   ON t.id          = c.topic_id
    LEFT JOIN school_edu.modules             m   ON m.course_id   = c.id
    LEFT JOIN school_edu.lessons             l   ON l.module_id   = m.id
                                                 AND l.is_published = TRUE
    LEFT JOIN school_edu.homeworks           hw  ON hw.lesson_id  = l.id
    LEFT JOIN school_edu.enrollments         e   ON e.course_id   = c.id
    LEFT JOIN school_fin.payments            p   ON p.course_id   = c.id
    LEFT JOIN school_audit.mv_course_completion mcc
        ON mcc.course_id = c.id
    WHERE c.id = p_course_id
    GROUP BY c.id, c.title, t.name, c.subject;
END;
$$;

COMMENT ON FUNCTION school_edu.fn_get_course_stats(UUID) IS
    'Полная статистика по одному курсу: модули, уроки, ДЗ, студенты, выручка, средний прогресс';


-- =============================================================
-- 3. fn_get_student_rank
--    Возвращает место студента в рейтинге по курсу
--    и его суммарный балл
-- =============================================================
CREATE OR REPLACE FUNCTION school_edu.fn_get_student_rank(
    p_student_id UUID,
    p_course_id  UUID
)
RETURNS TABLE (
    student_id      UUID,
    full_name       TEXT,
    course_id       UUID,
    total_score     NUMERIC,
    max_possible    NUMERIC,
    score_pct       NUMERIC,
    rank_in_course  BIGINT,
    total_students  BIGINT
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    -- Проверяем, что студент зачислен на курс
    IF NOT EXISTS (
        SELECT 1 FROM school_edu.enrollments
        WHERE student_id = p_student_id
          AND course_id  = p_course_id
          AND is_active  = TRUE
    ) THEN
        RAISE EXCEPTION
            'Студент % не зачислен на курс %', p_student_id, p_course_id;
    END IF;

    RETURN QUERY
    WITH ranked AS (
        SELECT
            e.student_id,
            school_core.fn_get_user_full_name(e.student_id)    AS full_name,
            e.course_id,
            COALESCE(SUM(hs.score), 0)                          AS total_score,
            COALESCE(SUM(hw.max_score), 0)                      AS max_possible,
            CASE
                WHEN COALESCE(SUM(hw.max_score), 0) = 0 THEN 0
                ELSE ROUND(SUM(hs.score)::NUMERIC
                     / SUM(hw.max_score) * 100, 1)
            END                                                 AS score_pct,
            RANK() OVER (
                ORDER BY COALESCE(SUM(hs.score), 0) DESC
            )                                                   AS rank_in_course,
            COUNT(*) OVER ()                                    AS total_students
        FROM school_edu.enrollments              e
        JOIN school_edu.modules                  m   ON m.course_id   = e.course_id
        JOIN school_edu.lessons                  l   ON l.module_id   = m.id
        JOIN school_edu.homeworks                hw  ON hw.lesson_id  = l.id
        LEFT JOIN school_edu.homework_submissions hs
            ON hs.homework_id = hw.id
           AND hs.student_id  = e.student_id
           AND hs.status IN ('checked', 'auto_checked')
        WHERE e.course_id  = p_course_id
          AND e.is_active  = TRUE
          AND l.is_published = TRUE
        GROUP BY e.student_id, e.course_id
    )
    SELECT
        r.student_id,
        r.full_name,
        r.course_id,
        r.total_score,
        r.max_possible,
        r.score_pct,
        r.rank_in_course,
        r.total_students
    FROM ranked r
    WHERE r.student_id = p_student_id;
END;
$$;

COMMENT ON FUNCTION school_edu.fn_get_student_rank(UUID, UUID) IS
    'Место студента в рейтинге курса по суммарным баллам за ДЗ';


-- =============================================================
-- 4. fn_calc_period_end
--    Рассчитывает дату окончания периода оплаты
--    на основе даты начала и типа подписки
-- =============================================================
CREATE OR REPLACE FUNCTION school_fin.fn_calc_period_end(
    p_period_start    DATE,
    p_subscription    school_fin.subscription_type
)
RETURNS DATE
LANGUAGE plpgsql
STABLE                          -- пользовательский ENUM не позволяет IMMUTABLE
AS $$
BEGIN
    RETURN CASE p_subscription
        WHEN 'monthly' THEN p_period_start + INTERVAL '1 month' - INTERVAL '1 day'
        WHEN 'yearly'  THEN p_period_start + INTERVAL '1 year'  - INTERVAL '1 day'
    END;
END;
$$;

COMMENT ON FUNCTION school_fin.fn_calc_period_end(DATE, school_fin.subscription_type) IS
    'Вычисляет дату окончания периода оплаты по дате начала и типу подписки';


-- =============================================================
-- 5. fn_is_student_enrolled
--    Проверяет, зачислен ли студент на курс (активное зачисление)
--    Возвращает BOOLEAN — удобно использовать в CHECK и бизнес-логике
-- =============================================================
CREATE OR REPLACE FUNCTION school_edu.fn_is_student_enrolled(
    p_student_id UUID,
    p_course_id  UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM school_edu.enrollments
        WHERE student_id = p_student_id
          AND course_id  = p_course_id
          AND is_active  = TRUE
    );
END;
$$;

COMMENT ON FUNCTION school_edu.fn_is_student_enrolled(UUID, UUID) IS
    'Возвращает TRUE, если студент активно зачислен на курс';


-- =============================================================
-- 6. fn_get_teacher_students
--    Возвращает список студентов преподавателя
--    (только по курсам, которые он ведёт)
--    Поддерживает фильтрацию по конкретному курсу
-- =============================================================
CREATE OR REPLACE FUNCTION school_edu.fn_get_teacher_students(
    p_teacher_id UUID,
    p_course_id  UUID DEFAULT NULL   -- NULL = все курсы преподавателя
)
RETURNS TABLE (
    student_id      UUID,
    full_name       TEXT,
    email           TEXT,
    course_id       UUID,
    course_title    TEXT,
    subject         TEXT,
    enrolled_at     TIMESTAMPTZ,
    total_score     NUMERIC,
    completed_pct   NUMERIC
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    -- Проверяем, что пользователь — преподаватель
    IF NOT EXISTS (
        SELECT 1 FROM school_core.users
        WHERE id = p_teacher_id AND role = 'teacher'
    ) THEN
        RAISE EXCEPTION 'Пользователь % не является преподавателем', p_teacher_id;
    END IF;

    RETURN QUERY
    SELECT
        u.id,
        school_core.fn_get_user_full_name(u.id),
        u.email::TEXT,
        c.id,
        c.title::TEXT,
        c.subject::TEXT,
        e.enrolled_at,
        COALESCE(sp.total_score::NUMERIC, 0),
        COALESCE(cc.completion_pct, 0)
    FROM school_edu.course_teachers          ct
    JOIN school_edu.courses                  c   ON c.id          = ct.course_id
    JOIN school_edu.enrollments              e   ON e.course_id   = c.id
                                                 AND e.is_active  = TRUE
    JOIN school_core.users                   u   ON u.id          = e.student_id
    -- Прогресс из материализованного представления
    LEFT JOIN school_audit.mv_course_completion cc
        ON cc.student_id = e.student_id
       AND cc.course_id  = c.id
    -- Баллы из материализованного представления
    LEFT JOIN school_audit.mv_student_scores sp
        ON sp.student_id = e.student_id
       AND sp.course_id  = c.id
    WHERE ct.teacher_id = p_teacher_id
      AND (p_course_id IS NULL OR c.id = p_course_id)
      AND u.is_active = TRUE
    ORDER BY c.title, u.last_name, u.first_name;
END;
$$;

COMMENT ON FUNCTION school_edu.fn_get_teacher_students(UUID, UUID) IS
    'Список студентов преподавателя с прогрессом. p_course_id=NULL — все курсы.';


-- =============================================================
-- 7. fn_get_monthly_revenue
--    Возвращает помесячную разбивку доходов за указанный период
--    Использует оконные функции для накопительного итога
-- =============================================================
CREATE OR REPLACE FUNCTION school_fin.fn_get_monthly_revenue(
    p_date_from DATE DEFAULT DATE_TRUNC('year', CURRENT_DATE)::DATE,
    p_date_to   DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    year            INT,
    month           INT,
    month_name      TEXT,
    revenue         NUMERIC,
    revenue_monthly NUMERIC,
    revenue_yearly  NUMERIC,
    payments_count  BIGINT,
    cumulative_revenue NUMERIC   -- накопительный итог
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF p_date_from > p_date_to THEN
        RAISE EXCEPTION 'Дата начала % не может быть позже даты окончания %',
            p_date_from, p_date_to;
    END IF;

    RETURN QUERY
    WITH monthly AS (
        SELECT
            EXTRACT(YEAR  FROM payment_date)::INT   AS yr,
            EXTRACT(MONTH FROM payment_date)::INT   AS mo,
            TO_CHAR(payment_date, 'TMMonth')        AS mo_name,
            COALESCE(SUM(amount), 0)                AS rev,
            COALESCE(SUM(amount)
                FILTER (WHERE subscription_type = 'monthly'), 0) AS rev_monthly,
            COALESCE(SUM(amount)
                FILTER (WHERE subscription_type = 'yearly'),  0) AS rev_yearly,
            COUNT(*)                                AS pay_cnt
        FROM school_fin.payments
        WHERE payment_date BETWEEN p_date_from AND p_date_to
        GROUP BY yr, mo, mo_name
    )
    SELECT
        m.yr,
        m.mo,
        m.mo_name,
        m.rev,
        m.rev_monthly,
        m.rev_yearly,
        m.pay_cnt,
        -- Накопительный итог с начала периода
        SUM(m.rev) OVER (
            ORDER BY m.yr, m.mo
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )
    FROM monthly m
    ORDER BY m.yr, m.mo;
END;
$$;

COMMENT ON FUNCTION school_fin.fn_get_monthly_revenue(DATE, DATE) IS
    'Помесячные доходы с накопительным итогом. По умолчанию — текущий год.';


-- =============================================================
-- 8. fn_get_course_progress_report
--    Полный отчёт по курсу с обходом студентов через CURSOR.
--    Итерирует по каждому студенту, собирает детальную
--    статистику и возвращает сводную таблицу.
--
--    Демонстрирует: CURSOR, LOOP, FETCH, CLOSE,
--    накопление результатов через временную таблицу.
-- =============================================================
CREATE OR REPLACE FUNCTION school_edu.fn_get_course_progress_report(
    p_course_id UUID
)
RETURNS TABLE (
    student_id          UUID,
    full_name           TEXT,
    email               TEXT,
    enrolled_at         TIMESTAMPTZ,
    completed_lessons   BIGINT,
    total_lessons       BIGINT,
    lessons_pct         NUMERIC,
    submitted_hw        BIGINT,
    total_hw            BIGINT,
    total_score         NUMERIC,
    max_score           NUMERIC,
    score_pct           NUMERIC,
    last_activity_at    TIMESTAMPTZ,
    status_label        TEXT
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    -- Курсор по всем активным студентам курса
    cur_students CURSOR FOR
        SELECT
            u.id            AS sid,
            u.email         AS semail,
            e.enrolled_at   AS senrolled_at
        FROM school_edu.enrollments  e
        JOIN school_core.users       u ON u.id = e.student_id
        WHERE e.course_id = p_course_id
          AND e.is_active = TRUE
          AND u.is_active = TRUE
        ORDER BY u.last_name, u.first_name;

    -- Переменные для текущей строки курсора
    v_student_id        UUID;
    v_email             TEXT;
    v_enrolled_at       TIMESTAMPTZ;

    -- Переменные для статистики по студенту
    v_full_name         TEXT;
    v_completed_lessons BIGINT;
    v_total_lessons     BIGINT;
    v_lessons_pct       NUMERIC;
    v_submitted_hw      BIGINT;
    v_total_hw          BIGINT;
    v_total_score       NUMERIC;
    v_max_score         NUMERIC;
    v_score_pct         NUMERIC;
    v_last_activity     TIMESTAMPTZ;
    v_status_label      TEXT;

    -- Счётчик для логирования
    v_processed         INT := 0;
BEGIN
    -- Проверяем существование курса
    IF NOT EXISTS (
        SELECT 1 FROM school_edu.courses WHERE id = p_course_id
    ) THEN
        RAISE EXCEPTION 'Курс с id=% не найден', p_course_id;
    END IF;

    -- Открываем курсор
    OPEN cur_students;

    LOOP
        -- Извлекаем следующую строку
        FETCH cur_students INTO v_student_id, v_email, v_enrolled_at;

        -- Выходим из цикла, если строк больше нет
        EXIT WHEN NOT FOUND;

        -- Полное имя студента
        v_full_name := school_core.fn_get_user_full_name(v_student_id);

        -- Прогресс по урокам
        SELECT
            COUNT(l.id),
            COUNT(lp.id) FILTER (WHERE lp.is_completed = TRUE)
        INTO v_total_lessons, v_completed_lessons
        FROM school_edu.modules              m
        JOIN school_edu.lessons              l   ON l.module_id   = m.id
        LEFT JOIN school_edu.lesson_progress lp
            ON lp.lesson_id  = l.id
           AND lp.student_id = v_student_id
        WHERE m.course_id    = p_course_id
          AND l.is_published = TRUE;

        v_lessons_pct := CASE
            WHEN COALESCE(v_total_lessons, 0) = 0 THEN 0
            ELSE ROUND(v_completed_lessons::NUMERIC / v_total_lessons * 100, 1)
        END;

        -- Статистика по ДЗ
        SELECT
            COUNT(hw.id),
            COUNT(hs.id) FILTER (WHERE hs.status IN ('checked','auto_checked')),
            COALESCE(SUM(hs.score)   FILTER (WHERE hs.status IN ('checked','auto_checked')), 0),
            COALESCE(SUM(hw.max_score), 0)
        INTO v_total_hw, v_submitted_hw, v_total_score, v_max_score
        FROM school_edu.modules              m
        JOIN school_edu.lessons              l   ON l.module_id   = m.id
        JOIN school_edu.homeworks            hw  ON hw.lesson_id  = l.id
        LEFT JOIN school_edu.homework_submissions hs
            ON hs.homework_id = hw.id
           AND hs.student_id  = v_student_id
        WHERE m.course_id    = p_course_id
          AND l.is_published = TRUE;

        v_score_pct := CASE
            WHEN COALESCE(v_max_score, 0) = 0 THEN 0
            ELSE ROUND(v_total_score::NUMERIC / v_max_score * 100, 1)
        END;

        -- Дата последней активности студента
        SELECT MAX(created_at)
        INTO v_last_activity
        FROM school_audit.activity_log
        WHERE user_id = v_student_id;

        -- Метка статуса студента
        v_status_label := CASE
            WHEN v_lessons_pct = 100                        THEN 'Курс завершён'
            WHEN v_last_activity < NOW() - INTERVAL '14 days'
                 OR v_last_activity IS NULL                 THEN 'Неактивен (14+ дней)'
            WHEN v_lessons_pct >= 50                        THEN 'Активно учится'
            WHEN v_lessons_pct > 0                          THEN 'Только начал'
            ELSE                                                 'Не приступал'
        END;

        v_processed := v_processed + 1;

        -- Присваиваем OUT-переменным значения перед RETURN NEXT
        student_id        := v_student_id;
        full_name         := v_full_name;
        email             := v_email;
        enrolled_at       := v_enrolled_at;
        completed_lessons := v_completed_lessons;
        total_lessons     := v_total_lessons;
        lessons_pct       := v_lessons_pct;
        submitted_hw      := v_submitted_hw;
        total_hw          := v_total_hw;
        total_score       := v_total_score;
        max_score         := v_max_score;
        score_pct         := v_score_pct;
        last_activity_at  := v_last_activity;
        status_label      := v_status_label;

        -- Возвращаем строку результата
        RETURN NEXT;

    END LOOP;

    -- Закрываем курсор
    CLOSE cur_students;

    -- Логируем факт построения отчёта
    RAISE NOTICE 'Отчёт по курсу % построен. Обработано студентов: %',
        p_course_id, v_processed;
END;
$$;

COMMENT ON FUNCTION school_edu.fn_get_course_progress_report(UUID) IS
    'Детальный отчёт по курсу с обходом студентов через CURSOR. '
    'Возвращает прогресс, баллы и статус каждого студента.';


-- =============================================================
-- 9. fn_validate_submission_score
--    Триггерная функция: проверяет, что выставленный балл
--    не превышает максимальный балл домашнего задания.
--    Вызывается триггером BEFORE INSERT OR UPDATE.
-- =============================================================
CREATE OR REPLACE FUNCTION school_edu.fn_validate_submission_score()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_max_score SMALLINT;
BEGIN
    -- Получаем максимальный балл для данного ДЗ
    SELECT max_score
    INTO v_max_score
    FROM school_edu.homeworks
    WHERE id = NEW.homework_id;

    -- Если балл указан — проверяем
    IF NEW.score IS NOT NULL AND NEW.score > v_max_score THEN
        RAISE EXCEPTION
            'Балл % превышает максимально допустимый % для ДЗ %',
            NEW.score, v_max_score, NEW.homework_id;
    END IF;

    -- Если балл указан — статус должен быть checked или auto_checked
    IF NEW.score IS NOT NULL AND NEW.status = 'submitted' THEN
        RAISE EXCEPTION
            'Нельзя выставить балл при статусе "submitted". '
            'Сначала измените статус на "checked" или "auto_checked".';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION school_edu.fn_validate_submission_score() IS
    'Триггерная функция: валидация балла ДЗ — не выше максимального';


-- =============================================================
-- 10. fn_auto_check_homework
--     Триггерная функция: если тип проверки ДЗ = 'auto',
--     автоматически выставляет максимальный балл и меняет статус.
--     Вызывается триггером AFTER INSERT на homework_submissions.
-- =============================================================
CREATE OR REPLACE FUNCTION school_edu.fn_auto_check_homework()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_check_type school_edu.check_type;
    v_max_score  SMALLINT;
BEGIN
    -- Получаем тип проверки и максимальный балл
    SELECT check_type, max_score
    INTO v_check_type, v_max_score
    FROM school_edu.homeworks
    WHERE id = NEW.homework_id;

    -- Автопроверка: выставляем максимальный балл
    IF v_check_type = 'auto' THEN
        UPDATE school_edu.homework_submissions
        SET
            score      = v_max_score,
            status     = 'auto_checked',
            checked_at = NOW()
        WHERE id = NEW.id;

        RAISE NOTICE
            'Автопроверка ДЗ %: студенту % выставлен балл %/%',
            NEW.homework_id, NEW.student_id, v_max_score, v_max_score;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION school_edu.fn_auto_check_homework() IS
    'Триггерная функция: при сдаче ДЗ с auto-проверкой выставляет максимальный балл';


-- =============================================================
-- 11. fn_update_updated_at
--     Универсальная триггерная функция для автоматического
--     обновления поля updated_at при любом UPDATE записи.
--     Подключается к таблицам users и courses.
-- =============================================================
CREATE OR REPLACE FUNCTION school_core.fn_update_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION school_core.fn_update_updated_at() IS
    'Универсальная триггерная функция: устанавливает updated_at = NOW() при UPDATE';

-- =============================================================
-- ОНЛАЙН-ШКОЛА: Шаг 4 — Триггеры и процедуры с транзакциями
-- =============================================================
-- ТРИГГЕРЫ:
--  1.  trg_update_users_updated_at        — auto updated_at на users
--  2.  trg_update_courses_updated_at      — auto updated_at на courses
--  3.  trg_validate_submission_score      — валидация балла ДЗ
--  4.  trg_auto_check_homework            — автопроверка ДЗ
--  5.  trg_log_user_enrollment            — лог зачисления студента
--  6.  trg_log_lesson_progress            — лог просмотра урока
--  7.  trg_check_teacher_role             — запрет назначить не-преподавателя
--  8.  trg_check_student_role             — запрет зачислить не-студента
--  9.  trg_lesson_progress_completed_at   — фиксация даты завершения урока
--  10. trg_refresh_mv_on_enrollment       — обновление MV при зачислении
--
-- ПРОЦЕДУРЫ:
--  1.  pr_enroll_student                  — зачисление студента на курс
--  2.  pr_record_payment                  — фиксация платежа
--  3.  pr_check_homework                  — проверка ДЗ преподавателем
--  4.  pr_deactivate_student              — деактивация студента
-- =============================================================


-- =============================================================
-- ТРИГГЕРЫ
-- =============================================================

-- -------------------------------------------------------------
-- 1. trg_update_users_updated_at
--    Автоматически обновляет updated_at при изменении users
-- -------------------------------------------------------------
CREATE TRIGGER trg_update_users_updated_at
    BEFORE UPDATE ON school_core.users
    FOR EACH ROW
    EXECUTE FUNCTION school_core.fn_update_updated_at();

COMMENT ON TRIGGER trg_update_users_updated_at ON school_core.users IS
    'Устанавливает updated_at = NOW() при каждом UPDATE пользователя';


-- -------------------------------------------------------------
-- 2. trg_update_courses_updated_at
--    Автоматически обновляет updated_at при изменении courses
-- -------------------------------------------------------------
CREATE TRIGGER trg_update_courses_updated_at
    BEFORE UPDATE ON school_edu.courses
    FOR EACH ROW
    EXECUTE FUNCTION school_core.fn_update_updated_at();

COMMENT ON TRIGGER trg_update_courses_updated_at ON school_edu.courses IS
    'Устанавливает updated_at = NOW() при каждом UPDATE курса';


-- -------------------------------------------------------------
-- 3. trg_validate_submission_score
--    BEFORE INSERT OR UPDATE на homework_submissions:
--    не даёт выставить балл выше максимального
-- -------------------------------------------------------------
CREATE TRIGGER trg_validate_submission_score
    BEFORE INSERT OR UPDATE ON school_edu.homework_submissions
    FOR EACH ROW
    EXECUTE FUNCTION school_edu.fn_validate_submission_score();

COMMENT ON TRIGGER trg_validate_submission_score
    ON school_edu.homework_submissions IS
    'Валидация балла ДЗ: score не может превышать homeworks.max_score';


-- -------------------------------------------------------------
-- 4. trg_auto_check_homework
--    AFTER INSERT на homework_submissions:
--    если ДЗ с auto-проверкой — сразу ставит максимальный балл
-- -------------------------------------------------------------
CREATE TRIGGER trg_auto_check_homework
    AFTER INSERT ON school_edu.homework_submissions
    FOR EACH ROW
    EXECUTE FUNCTION school_edu.fn_auto_check_homework();

COMMENT ON TRIGGER trg_auto_check_homework
    ON school_edu.homework_submissions IS
    'При сдаче ДЗ с типом auto — автоматически выставляет максимальный балл';


-- -------------------------------------------------------------
-- 5. trg_log_user_enrollment
--    AFTER INSERT OR UPDATE на enrollments:
--    пишет в activity_log факт зачисления или деактивации
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION school_edu.fn_log_enrollment_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO school_audit.activity_log
            (user_id, action, entity_type, entity_id, metadata)
        VALUES (
            NEW.student_id,
            'enroll',
            'course',
            NEW.course_id,
            JSONB_BUILD_OBJECT(
                'enrollment_id', NEW.id,
                'enrolled_at',   NEW.enrolled_at
            )
        );

    ELSIF TG_OP = 'UPDATE' AND OLD.is_active = TRUE AND NEW.is_active = FALSE THEN
        INSERT INTO school_audit.activity_log
            (user_id, action, entity_type, entity_id, metadata)
        VALUES (
            NEW.student_id,
            'unenroll',
            'course',
            NEW.course_id,
            JSONB_BUILD_OBJECT(
                'enrollment_id', NEW.id,
                'reason',        'deactivated'
            )
        );
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_log_user_enrollment
    AFTER INSERT OR UPDATE ON school_edu.enrollments
    FOR EACH ROW
    EXECUTE FUNCTION school_edu.fn_log_enrollment_change();

COMMENT ON TRIGGER trg_log_user_enrollment ON school_edu.enrollments IS
    'Логирует зачисление (enroll) и отчисление (unenroll) в activity_log';


-- -------------------------------------------------------------
-- 6. trg_log_lesson_progress
--    AFTER INSERT OR UPDATE на lesson_progress:
--    логирует первый просмотр урока и его завершение
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION school_edu.fn_log_lesson_progress()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Первый просмотр урока (INSERT)
    IF TG_OP = 'INSERT' THEN
        INSERT INTO school_audit.activity_log
            (user_id, action, entity_type, entity_id, metadata)
        VALUES (
            NEW.student_id,
            'view_lesson',
            'lesson',
            NEW.lesson_id,
            JSONB_BUILD_OBJECT('first_view', TRUE)
        );

    -- Урок отмечен как завершённый (UPDATE is_completed: false → true)
    ELSIF TG_OP = 'UPDATE'
        AND OLD.is_completed = FALSE
        AND NEW.is_completed = TRUE
    THEN
        INSERT INTO school_audit.activity_log
            (user_id, action, entity_type, entity_id, metadata)
        VALUES (
            NEW.student_id,
            'complete_lesson',
            'lesson',
            NEW.lesson_id,
            JSONB_BUILD_OBJECT('completed_at', NEW.completed_at)
        );
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_log_lesson_progress
    AFTER INSERT OR UPDATE ON school_edu.lesson_progress
    FOR EACH ROW
    EXECUTE FUNCTION school_edu.fn_log_lesson_progress();

COMMENT ON TRIGGER trg_log_lesson_progress ON school_edu.lesson_progress IS
    'Логирует первый просмотр урока и факт завершения в activity_log';


-- -------------------------------------------------------------
-- 7. trg_check_teacher_role
--    BEFORE INSERT OR UPDATE на course_teachers:
--    запрещает назначить на курс пользователя с ролью != teacher
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION school_edu.fn_check_teacher_role()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_role school_core.user_role;
BEGIN
    SELECT role INTO v_role
    FROM school_core.users
    WHERE id = NEW.teacher_id;

    IF v_role IS NULL THEN
        RAISE EXCEPTION
            'Пользователь % не существует', NEW.teacher_id;
    END IF;

    IF v_role <> 'teacher' THEN
        RAISE EXCEPTION
            'Пользователь % имеет роль "%", а не "teacher". '
            'Назначить на курс можно только преподавателя.',
            NEW.teacher_id, v_role;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_check_teacher_role
    BEFORE INSERT OR UPDATE ON school_edu.course_teachers
    FOR EACH ROW
    EXECUTE FUNCTION school_edu.fn_check_teacher_role();

COMMENT ON TRIGGER trg_check_teacher_role ON school_edu.course_teachers IS
    'Запрещает назначить на курс пользователя с ролью, отличной от teacher';


-- -------------------------------------------------------------
-- 8. trg_check_student_role
--    BEFORE INSERT OR UPDATE на enrollments:
--    запрещает зачислить на курс не-студента
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION school_edu.fn_check_student_role()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_role school_core.user_role;
BEGIN
    SELECT role INTO v_role
    FROM school_core.users
    WHERE id = NEW.student_id;

    IF v_role IS NULL THEN
        RAISE EXCEPTION
            'Пользователь % не существует', NEW.student_id;
    END IF;

    IF v_role <> 'student' THEN
        RAISE EXCEPTION
            'Пользователь % имеет роль "%", а не "student". '
            'Зачислить на курс можно только студента.',
            NEW.student_id, v_role;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_check_student_role
    BEFORE INSERT OR UPDATE ON school_edu.enrollments
    FOR EACH ROW
    EXECUTE FUNCTION school_edu.fn_check_student_role();

COMMENT ON TRIGGER trg_check_student_role ON school_edu.enrollments IS
    'Запрещает зачислить на курс пользователя с ролью, отличной от student';


-- -------------------------------------------------------------
-- 9. trg_lesson_progress_completed_at
--    BEFORE UPDATE на lesson_progress:
--    автоматически проставляет completed_at при is_completed = true
--    и обнуляет его при откате
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION school_edu.fn_set_completed_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Урок только что отмечен завершённым
    IF NEW.is_completed = TRUE AND OLD.is_completed = FALSE THEN
        NEW.completed_at   := NOW();
        NEW.last_viewed_at := NOW();

    -- Урок откатили в незавершённое состояние
    ELSIF NEW.is_completed = FALSE AND OLD.is_completed = TRUE THEN
        NEW.completed_at := NULL;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_lesson_progress_completed_at
    BEFORE UPDATE ON school_edu.lesson_progress
    FOR EACH ROW
    EXECUTE FUNCTION school_edu.fn_set_completed_at();

COMMENT ON TRIGGER trg_lesson_progress_completed_at
    ON school_edu.lesson_progress IS
    'Автоматически проставляет / обнуляет completed_at при изменении is_completed';


-- -------------------------------------------------------------
-- 10. trg_refresh_mv_on_enrollment
--     AFTER INSERT OR UPDATE на enrollments:
--     помечает, что материализованные представления устарели
--     (через вставку записи в служебную таблицу-флаг).
--
--     Реальный REFRESH делается отложенно (через задание
--     или явным вызовом refresh_all_materialized_views),
--     чтобы не тормозить каждую транзакцию зачисления.
-- -------------------------------------------------------------

-- Служебная таблица-флаг для отложенного обновления MV
CREATE TABLE IF NOT EXISTS school_audit.mv_refresh_queue (
    id           BIGSERIAL    PRIMARY KEY,
    view_name    TEXT         NOT NULL,
    triggered_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    processed    BOOLEAN      NOT NULL DEFAULT FALSE
);

COMMENT ON TABLE school_audit.mv_refresh_queue IS
    'Очередь запросов на обновление материализованных представлений';

CREATE OR REPLACE FUNCTION school_audit.fn_queue_mv_refresh()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO school_audit.mv_refresh_queue (view_name)
    VALUES ('mv_admin_dashboard'),
           ('mv_student_scores'),
           ('mv_course_completion'),
           ('mv_teacher_workload');

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_refresh_mv_on_enrollment
    AFTER INSERT OR UPDATE ON school_edu.enrollments
    FOR EACH STATEMENT          -- один раз на весь оператор, не на каждую строку
    EXECUTE FUNCTION school_audit.fn_queue_mv_refresh();

COMMENT ON TRIGGER trg_refresh_mv_on_enrollment ON school_edu.enrollments IS
    'Добавляет задания на обновление MV в очередь при изменении зачислений';


-- =============================================================
-- ПРОЦЕДУРЫ С ТРАНЗАКЦИЯМИ
-- =============================================================

-- -------------------------------------------------------------
-- ПРОЦЕДУРА 1: pr_enroll_student
--    Зачисляет студента на курс.
--    Если студент уже был зачислен, но деактивирован — реактивирует.
--    Проверяет: роль студента, существование курса, активность курса.
--    Транзакция: BEGIN → проверки → INSERT/UPDATE → COMMIT
--                При любой ошибке — ROLLBACK
-- -------------------------------------------------------------
CREATE OR REPLACE PROCEDURE school_edu.pr_enroll_student(
    p_student_id   UUID,
    p_course_id    UUID,
    p_enrolled_by  UUID    -- UUID администратора, выполняющего зачисление
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_student_role  school_core.user_role;
    v_course_active BOOLEAN;
    v_course_title  TEXT;
    v_existing_id   UUID;
    v_is_active     BOOLEAN;
BEGIN
    -- 1. Проверяем, что администратор существует и имеет роль admin
    IF NOT EXISTS (
        SELECT 1 FROM school_core.users
        WHERE id = p_enrolled_by AND role = 'admin' AND is_active = TRUE
    ) THEN
        RAISE EXCEPTION
            'Пользователь % не является активным администратором', p_enrolled_by;
    END IF;

    -- 2. Получаем роль студента
    SELECT role INTO v_student_role
    FROM school_core.users
    WHERE id = p_student_id AND is_active = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Студент % не найден или деактивирован', p_student_id;
    END IF;

    IF v_student_role <> 'student' THEN
        RAISE EXCEPTION
            'Пользователь % имеет роль "%" — зачислить можно только студента',
            p_student_id, v_student_role;
    END IF;

    -- 3. Проверяем курс
    SELECT is_active, title INTO v_course_active, v_course_title
    FROM school_edu.courses
    WHERE id = p_course_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Курс % не найден', p_course_id;
    END IF;

    IF v_course_active = FALSE THEN
        RAISE EXCEPTION
            'Курс "%" (%) деактивирован и недоступен для зачисления',
            v_course_title, p_course_id;
    END IF;

    -- 4. Проверяем, не зачислен ли студент уже
    SELECT id, is_active INTO v_existing_id, v_is_active
    FROM school_edu.enrollments
    WHERE student_id = p_student_id AND course_id = p_course_id;

    IF FOUND THEN
        IF v_is_active = TRUE THEN
            -- Студент уже активно зачислен — ничего не делаем
            RAISE NOTICE
                'Студент % уже активно зачислен на курс "%"',
                p_student_id, v_course_title;
            RETURN;
        ELSE
            -- Студент был зачислен, но деактивирован — реактивируем
            UPDATE school_edu.enrollments
            SET
                is_active   = TRUE,
                enrolled_at = NOW()
            WHERE id = v_existing_id;

            RAISE NOTICE
                'Студент % повторно зачислен на курс "%"',
                p_student_id, v_course_title;
        END IF;
    ELSE
        -- Новое зачисление
        INSERT INTO school_edu.enrollments
            (student_id, course_id)
        VALUES
            (p_student_id, p_course_id);

        RAISE NOTICE
            'Студент % успешно зачислен на курс "%"',
            p_student_id, v_course_title;
    END IF;

    -- 5. Логируем действие администратора
    INSERT INTO school_audit.activity_log
        (user_id, action, entity_type, entity_id, metadata)
    VALUES (
        p_enrolled_by,
        'admin_enroll',
        'enrollment',
        p_course_id,
        JSONB_BUILD_OBJECT(
            'student_id',  p_student_id,
            'course_id',   p_course_id,
            'course_title', v_course_title
        )
    );

    -- ===== КОНЕЦ ОСНОВНОЙ ЛОГИКИ =====

EXCEPTION
    WHEN OTHERS THEN
        RAISE;  -- откат происходит автоматически, пробрасываем ошибку
END;
$$;

COMMENT ON PROCEDURE school_edu.pr_enroll_student(UUID, UUID, UUID) IS
    'Зачисляет студента на курс. Проверяет роли, активность курса, '
    'реактивирует при повторном зачислении. Логирует действие администратора.';


-- -------------------------------------------------------------
-- ПРОЦЕДУРА 2: pr_record_payment
--    Фиксирует факт оплаты студентом курса.
--    Проверяет: зачисление студента, тип подписки, сумму.
--    Автоматически рассчитывает period_end через fn_calc_period_end.
--    Транзакция с явным BEGIN / COMMIT / ROLLBACK.
-- -------------------------------------------------------------
CREATE OR REPLACE PROCEDURE school_fin.pr_record_payment(
    p_student_id        UUID,
    p_course_id         UUID,
    p_amount            NUMERIC,
    p_subscription_type school_fin.subscription_type,
    p_period_start      DATE,
    p_created_by        UUID,
    p_notes             TEXT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_period_end    DATE;
    v_course_title  TEXT;
    v_expected_price NUMERIC;
    v_payment_id    UUID;
BEGIN
    -- 1. Проверяем, что фиксирует администратор
    IF NOT EXISTS (
        SELECT 1 FROM school_core.users
        WHERE id = p_created_by AND role = 'admin' AND is_active = TRUE
    ) THEN
        RAISE EXCEPTION
            'Пользователь % не является активным администратором', p_created_by;
    END IF;

    -- 2. Проверяем, что студент зачислен на курс
    IF NOT school_edu.fn_is_student_enrolled(p_student_id, p_course_id) THEN
        RAISE EXCEPTION
            'Студент % не зачислен на курс %. '
            'Сначала выполните зачисление через pr_enroll_student.',
            p_student_id, p_course_id;
    END IF;

    -- 3. Получаем данные курса и ожидаемую цену
    SELECT
        title,
        CASE p_subscription_type
            WHEN 'monthly' THEN price_monthly
            WHEN 'yearly'  THEN price_yearly
        END
    INTO v_course_title, v_expected_price
    FROM school_edu.courses
    WHERE id = p_course_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Курс % не найден', p_course_id;
    END IF;

    -- 4. Предупреждаем, если сумма отличается от прайса
    --    (администратор может ввести скидку — не блокируем, но логируем)
    IF v_expected_price IS NOT NULL AND p_amount <> v_expected_price THEN
        RAISE NOTICE
            'Внимание: сумма оплаты % отличается от прайса % для курса "%". '
            'Платёж принят.',
            p_amount, v_expected_price, v_course_title;
    END IF;

    -- 5. Рассчитываем дату окончания периода
    v_period_end := school_fin.fn_calc_period_end(p_period_start, p_subscription_type);

    -- 6. Вставляем платёж
    INSERT INTO school_fin.payments (
        student_id,
        course_id,
        amount,
        subscription_type,
        payment_date,
        period_start,
        period_end,
        notes,
        created_by
    )
    VALUES (
        p_student_id,
        p_course_id,
        p_amount,
        p_subscription_type,
        CURRENT_DATE,
        p_period_start,
        v_period_end,
        p_notes,
        p_created_by
    )
    RETURNING id INTO v_payment_id;

    -- 7. Логируем действие
    INSERT INTO school_audit.activity_log
        (user_id, action, entity_type, entity_id, metadata)
    VALUES (
        p_created_by,
        'record_payment',
        'payment',
        v_payment_id,
        JSONB_BUILD_OBJECT(
            'student_id',        p_student_id,
            'course_id',         p_course_id,
            'course_title',      v_course_title,
            'amount',            p_amount,
            'subscription_type', p_subscription_type,
            'period_start',      p_period_start,
            'period_end',        v_period_end
        )
    );

    RAISE NOTICE
        'Платёж зафиксирован: студент %, курс "%" (%), сумма %, период % — %',
        p_student_id, v_course_title, p_subscription_type,
        p_amount, p_period_start, v_period_end;

EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$$;

COMMENT ON PROCEDURE school_fin.pr_record_payment(UUID,UUID,NUMERIC,school_fin.subscription_type,DATE,UUID,TEXT) IS
    'Фиксирует оплату студента за курс. Проверяет зачисление, '
    'рассчитывает период, предупреждает при отклонении суммы от прайса.';


-- -------------------------------------------------------------
-- ПРОЦЕДУРА 3: pr_check_homework
--    Преподаватель проверяет ДЗ студента и выставляет балл.
--    Проверяет: право проверки (только преподаватель курса),
--    статус работы (только submitted), валидность балла.
--    Транзакция: откат при ошибке через блок EXCEPTION.
-- -------------------------------------------------------------
CREATE OR REPLACE PROCEDURE school_edu.pr_check_homework(
    p_submission_id UUID,
    p_teacher_id    UUID,
    p_score         SMALLINT,
    p_comment       TEXT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_homework_id   UUID;
    v_student_id    UUID;
    v_course_id     UUID;
    v_check_type    school_edu.check_type;
    v_max_score     SMALLINT;
    v_current_status school_edu.submission_status;
    v_hw_title      TEXT;
BEGIN
    -- 1. Получаем данные о сдаче ДЗ
    SELECT
        hs.homework_id,
        hs.student_id,
        hs.status,
        hw.check_type,
        hw.max_score,
        hw.title
    INTO
        v_homework_id,
        v_student_id,
        v_current_status,
        v_check_type,
        v_max_score,
        v_hw_title
    FROM school_edu.homework_submissions  hs
    JOIN school_edu.homeworks             hw ON hw.id = hs.homework_id
    WHERE hs.id = p_submission_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Сдача ДЗ % не найдена', p_submission_id;
    END IF;

    -- 2. Автопроверяемое ДЗ нельзя проверять вручную
    IF v_check_type = 'auto' THEN
        RAISE EXCEPTION
            'ДЗ "%" проверяется автоматически. Ручная проверка недоступна.',
            v_hw_title;
    END IF;

    -- 3. Можно проверять только работы в статусе submitted
    IF v_current_status <> 'submitted' THEN
        RAISE EXCEPTION
            'Сдача ДЗ % имеет статус "%" и уже была проверена',
            p_submission_id, v_current_status;
    END IF;

    -- 4. Проверяем, что проверяющий — преподаватель этого курса
    SELECT m.course_id INTO v_course_id
    FROM school_edu.homeworks   hw
    JOIN school_edu.lessons      l ON l.id        = hw.lesson_id
    JOIN school_edu.modules      m ON m.id        = l.module_id
    WHERE hw.id = v_homework_id;

    IF NOT EXISTS (
        SELECT 1 FROM school_edu.course_teachers
        WHERE course_id  = v_course_id
          AND teacher_id = p_teacher_id
    ) THEN
        RAISE EXCEPTION
            'Преподаватель % не ведёт курс, которому принадлежит это ДЗ',
            p_teacher_id;
    END IF;

    -- 5. Валидация балла
    IF p_score < 0 OR p_score > v_max_score THEN
        RAISE EXCEPTION
            'Балл % недопустим. Допустимый диапазон: 0 — %',
            p_score, v_max_score;
    END IF;

    -- 6. Обновляем запись о сдаче
    UPDATE school_edu.homework_submissions
    SET
        score      = p_score,
        status     = 'checked',
        checked_by = p_teacher_id,
        checked_at = NOW()
    WHERE id = p_submission_id;

    -- 7. Логируем проверку
    INSERT INTO school_audit.activity_log
        (user_id, action, entity_type, entity_id, metadata)
    VALUES (
        p_teacher_id,
        'check_homework',
        'homework_submission',
        p_submission_id,
        JSONB_BUILD_OBJECT(
            'homework_id',  v_homework_id,
            'student_id',   v_student_id,
            'score',        p_score,
            'max_score',    v_max_score,
            'comment',      p_comment
        )
    );

    RAISE NOTICE
        'ДЗ "%" проверено: студент %, балл %/%',
        v_hw_title, v_student_id, p_score, v_max_score;

EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$$;

COMMENT ON PROCEDURE school_edu.pr_check_homework(UUID, UUID, SMALLINT, TEXT) IS
    'Преподаватель проверяет ДЗ студента: валидирует права, балл, статус. '
    'Обновляет submission и пишет в activity_log.';


-- -------------------------------------------------------------
-- ПРОЦЕДУРА 4: pr_deactivate_student
--    Деактивирует студента и все его зачисления.
--    Многошаговая операция в одной транзакции:
--    1) деактивация пользователя
--    2) деактивация всех зачислений
--    3) лог каждого отчисления
--    При ошибке на любом шаге — полный откат.
-- -------------------------------------------------------------
CREATE OR REPLACE PROCEDURE school_edu.pr_deactivate_student(
    p_student_id  UUID,
    p_admin_id    UUID,
    p_reason      TEXT DEFAULT 'Деактивация администратором'
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_full_name         TEXT;
    v_enrollment_record RECORD;
    v_affected_courses  INT := 0;
BEGIN
    -- 1. Проверяем администратора
    IF NOT EXISTS (
        SELECT 1 FROM school_core.users
        WHERE id = p_admin_id AND role = 'admin' AND is_active = TRUE
    ) THEN
        RAISE EXCEPTION
            'Пользователь % не является активным администратором', p_admin_id;
    END IF;

    -- 2. Получаем данные студента
    SELECT school_core.fn_get_user_full_name(p_student_id)
    INTO v_full_name;

    IF NOT EXISTS (
        SELECT 1 FROM school_core.users
        WHERE id = p_student_id AND role = 'student'
    ) THEN
        RAISE EXCEPTION
            'Студент % не найден', p_student_id;
    END IF;

    -- 3. Деактивируем пользователя
    UPDATE school_core.users
    SET is_active = FALSE
    WHERE id = p_student_id AND is_active = TRUE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Студент % уже был деактивирован', p_student_id;
    END IF;

    -- 4. Перебираем все активные зачисления и деактивируем каждое
    --    (триггер trg_log_user_enrollment запишет unenroll в лог автоматически)
    FOR v_enrollment_record IN
        SELECT id, course_id
        FROM school_edu.enrollments
        WHERE student_id = p_student_id AND is_active = TRUE
    LOOP
        UPDATE school_edu.enrollments
        SET is_active = FALSE
        WHERE id = v_enrollment_record.id;

        v_affected_courses := v_affected_courses + 1;
    END LOOP;

    -- 5. Общий лог действия администратора
    INSERT INTO school_audit.activity_log
        (user_id, action, entity_type, entity_id, metadata)
    VALUES (
        p_admin_id,
        'deactivate_student',
        'user',
        p_student_id,
        JSONB_BUILD_OBJECT(
            'student_name',     v_full_name,
            'reason',           p_reason,
            'courses_affected', v_affected_courses
        )
    );

    RAISE NOTICE
        'Студент "%" (%) деактивирован. Отчислен с % курс(ов). Причина: %',
        v_full_name, p_student_id, v_affected_courses, p_reason;

EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$$;

COMMENT ON PROCEDURE school_edu.pr_deactivate_student(UUID, UUID, TEXT) IS
    'Деактивирует студента и все его зачисления в одной транзакции. '
    'Триггер на enrollments автоматически пишет unenroll в activity_log.';


-- =============================================================
-- ПРИМЕР ЯВНОЙ ТРАНЗАКЦИИ: зачисление + оплата одним блоком
-- =============================================================
-- Этот блок демонстрирует использование процедур
-- внутри явной клиентской транзакции BEGIN / COMMIT / ROLLBACK.
-- Запускать вручную с реальными UUID.
-- =============================================================
/*
BEGIN;

    -- Шаг 1: зачислить студента
    CALL school_edu.pr_enroll_student(
        '00000000-0000-0000-0000-000000000001',   -- student_id
        '00000000-0000-0000-0000-000000000010',   -- course_id
        '00000000-0000-0000-0000-000000000099'    -- admin_id
    );

    -- Шаг 2: зафиксировать оплату
    CALL school_fin.pr_record_payment(
        '00000000-0000-0000-0000-000000000001',   -- student_id
        '00000000-0000-0000-0000-000000000010',   -- course_id
        4900.00,                                  -- amount
        'yearly',                                 -- subscription_type
        CURRENT_DATE,                             -- period_start
        '00000000-0000-0000-0000-000000000099',   -- admin_id
        'Оплата за учебный год 2024-2025'         -- notes
    );

COMMIT;
-- При ошибке на любом шаге: ROLLBACK;
*/
