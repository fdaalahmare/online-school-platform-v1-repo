-- =============================================================
-- ОНЛАЙН-ШКОЛА: 05_report_students.sql
-- Отчёт по студентам: прогресс, баллы, активность
-- Запускать ПОСЛЕ 01_setup.sql и 02_test_data.sql
-- =============================================================

--
--============================================================'
--  ОТЧЁТ ПО СТУДЕНТАМ'
--============================================================'


-- -------------------------------------------------------------
-- 1. ОБЩИЙ ПРОГРЕСС КАЖДОГО СТУДЕНТА
-- -------------------------------------------------------------
--
-->>> 1. ПРОГРЕСС И БАЛЛЫ ПО КАЖДОМУ СТУДЕНТУ'
--------------------------------------------------------------'

SELECT
    student_name                AS "Студент",
    course_title                AS "Курс",
    lessons_progress_pct        AS "Уроков %",
    submitted_homeworks || '/' || total_homeworks
                                AS "ДЗ сдано",
    total_score || '/' || max_possible_score
                                AS "Баллы",
    score_pct                   AS "Балл %",
    CASE
        WHEN lessons_progress_pct = 100         THEN 'Завершён'
        WHEN lessons_progress_pct >= 50         THEN 'В процессе'
        WHEN lessons_progress_pct > 0           THEN 'Начат'
        ELSE                                         'Не начат'
    END                         AS "Статус"
FROM school_edu.v_student_progress
ORDER BY score_pct DESC, lessons_progress_pct DESC;


-- -------------------------------------------------------------
-- 2. РЕЙТИНГ СТУДЕНТОВ ПО БАЛЛАМ ВНУТРИ КУРСОВ
-- -------------------------------------------------------------
--
-->>> 2. РЕЙТИНГ СТУДЕНТОВ ПО КУРСАМ'
--------------------------------------------------------------'

SELECT
    rank_in_course              AS "Место",
    full_name                   AS "Студент",
    course_title                AS "Курс",
    topic_name                  AS "Тема",
    total_score                 AS "Набрано",
    max_possible_score          AS "Из",
    score_pct                   AS "Балл %"
FROM school_audit.mv_student_scores
ORDER BY course_title, rank_in_course;


-- -------------------------------------------------------------
-- 3. НЕСДАННЫЕ ДОМАШНИЕ ЗАДАНИЯ
-- -------------------------------------------------------------
--
-->>> 3. НЕСДАННЫЕ ДОМАШНИЕ ЗАДАНИЯ'
--------------------------------------------------------------'

WITH all_required AS (
    SELECT
        e.student_id,
        hw.id       AS homework_id,
        hw.title    AS homework_title,
        hw.check_type,
        l.title     AS lesson_title,
        m.title     AS module_title,
        c.id        AS course_id,
        c.title     AS course_title
    FROM school_edu.enrollments  e
    JOIN school_edu.modules      m   ON m.course_id  = e.course_id
	JOIN school_edu.courses      c   ON c.id         = e.course_id 
    JOIN school_edu.lessons      l   ON l.module_id  = m.id
    JOIN school_edu.homeworks    hw  ON hw.lesson_id = l.id
    WHERE e.is_active = TRUE AND l.is_published = TRUE
)
SELECT
    school_core.fn_get_user_full_name(ar.student_id)
                                AS "Студент",
    ar.course_title             AS "Курс",
    ar.module_title             AS "Модуль",
    ar.lesson_title             AS "Урок",
    ar.homework_title           AS "Домашнее задание",
    CASE ar.check_type
        WHEN 'manual' THEN 'Ручная'
        WHEN 'auto'   THEN 'Авто'
    END                         AS "Проверка"
FROM all_required ar
LEFT JOIN school_edu.homework_submissions hs
    ON hs.homework_id = ar.homework_id
   AND hs.student_id  = ar.student_id
WHERE hs.id IS NULL
ORDER BY ar.course_title, ar.student_id, ar.module_title;


-- -------------------------------------------------------------
-- 4. СТАТУС ДЗ ПО КАЖДОМУ СТУДЕНТУ
-- -------------------------------------------------------------

-->>> 4. СТАТУС ВСЕХ ДОМАШНИХ ЗАДАНИЙ'
--------------------------------------------------------------'

SELECT
    school_core.fn_get_user_full_name(hs.student_id)
                                AS "Студент",
    c.title                     AS "Курс",
    hw.title                    AS "Домашнее задание",
    hw.max_score                AS "Макс. балл",
    COALESCE(hs.score::TEXT, '—')
                                AS "Балл",
    CASE hs.status
        WHEN 'submitted'    THEN '🟡 Ожидает проверки'
        WHEN 'checked'      THEN '🟢 Проверено'
        WHEN 'auto_checked' THEN '🔵 Авто-проверено'
    END                         AS "Статус",
    TO_CHAR(hs.submitted_at, 'DD.MM.YYYY HH24:MI')
                                AS "Сдано",
    TO_CHAR(hs.checked_at,   'DD.MM.YYYY HH24:MI')
                                AS "Проверено"
FROM school_edu.homework_submissions  hs
JOIN school_edu.homeworks             hw  ON hw.id       = hs.homework_id
JOIN school_edu.lessons               l   ON l.id        = hw.lesson_id
JOIN school_edu.modules               m   ON m.id        = l.module_id
JOIN school_edu.courses               c   ON c.id        = m.course_id
ORDER BY c.title,
    school_core.fn_get_user_full_name(hs.student_id),
    hs.submitted_at;


-- -------------------------------------------------------------
-- 5. АКТИВНОСТЬ СТУДЕНТОВ
-- -------------------------------------------------------------

-->>> 5. АКТИВНОСТЬ СТУДЕНТОВ (последние действия)'
--------------------------------------------------------------'

SELECT
    school_core.fn_get_user_full_name(u.id)
                                AS "Студент",
    u.email                     AS "Email",
    COUNT(al.id)                AS "Действий всего",
    COUNT(al.id) FILTER (
        WHERE al.action = 'view_lesson'
    )                           AS "Просмотров уроков",
    COUNT(al.id) FILTER (
        WHERE al.action = 'complete_lesson'
    )                           AS "Уроков завершено",
    COUNT(al.id) FILTER (
        WHERE al.action = 'submit_hw'
    )                           AS "ДЗ сдано",
    COUNT(DISTINCT DATE_TRUNC('day', al.created_at))
                                AS "Активных дней",
    TO_CHAR(MAX(al.created_at), 'DD.MM.YYYY HH24:MI')
                                AS "Последняя активность"
FROM school_core.users          u
LEFT JOIN school_audit.activity_log al ON al.user_id = u.id
WHERE u.role = 'student' AND u.is_active = TRUE
GROUP BY u.id, u.email, u.last_name, u.first_name
ORDER BY MAX(al.created_at) DESC NULLS LAST;


-- -------------------------------------------------------------
-- 6. ВЫЗОВ ФУНКЦИИ: детальный отчёт по курсу (CURSOR)
-- -------------------------------------------------------------

-->>> 6. ДЕТАЛЬНЫЙ ОТЧЁТ ПО КУРСУ (ЕГЭ Математика)'
--   (через функцию fn_get_course_progress_report с CURSOR)'
--------------------------------------------------------------'

SELECT
    full_name                   AS "Студент",
    email                       AS "Email",
    completed_lessons || '/' || total_lessons
                                AS "Уроков",
    lessons_pct                 AS "Прогресс %",
    submitted_hw || '/' || total_hw
                                AS "ДЗ",
    total_score || '/' || max_score
                                AS "Баллы",
    score_pct                   AS "Балл %",
    COALESCE(
        TO_CHAR(last_activity_at, 'DD.MM.YYYY'), 'Нет данных'
    )                           AS "Последняя активность",
    status_label                AS "Статус"
FROM school_edu.fn_get_course_progress_report(
    '00000000-0000-0000-0002-000000000001'   -- ЕГЭ Математика
)
ORDER BY score_pct DESC;


