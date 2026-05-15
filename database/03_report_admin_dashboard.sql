-- =============================================================
-- ОНЛАЙН-ШКОЛА: 03_report_admin_dashboard.sql
-- Панель администратора — все основные виджеты
-- Запускать ПОСЛЕ 01_setup.sql и 02_test_data.sql
-- =============================================================

-- =============================================================
--    ПАНЕЛЬ АДМИНИСТРАТОРА — ОНЛАЙН-ШКОЛА'
-- =============================================================

-- -------------------------------------------------------------
-- 1. ГЛАВНАЯ СВОДКА ПЛАТФОРМЫ
-- -------------------------------------------------------------

-- >>> 1. ГЛАВНАЯ СВОДКА ПЛАТФОРМЫ
-- =============================================================

SELECT
    total_active_students       AS "Активных студентов",
    total_active_teachers       AS "Активных преподавателей",
    total_active_courses        AS "Активных курсов",
    total_active_enrollments    AS "Активных зачислений",
    pending_hw_checks           AS "ДЗ ожидают проверки",
    total_submissions           AS "Всего сдач ДЗ",
    revenue_current_month       AS "Доход за месяц (руб)",
    revenue_current_year        AS "Доход за год (руб)",
    revenue_total               AS "Доход всего (руб)",
    active_users_last_7days     AS "Активных за 7 дней",
    TO_CHAR(next_webinar_at, 'DD.MM.YYYY HH24:MI')
                                AS "Ближайший вебинар",
    TO_CHAR(refreshed_at, 'DD.MM.YYYY HH24:MI')
                                AS "Данные актуальны на"
FROM school_audit.mv_admin_dashboard;


-- -------------------------------------------------------------
-- 2. СПИСОК СТУДЕНТОВ С АКТИВНОСТЬЮ
-- -------------------------------------------------------------
-- 
-- >>> 2. СТУДЕНТЫ — АКТИВНОСТЬ И КУРСЫ
-- ------------------------------------------------------------'

SELECT
    full_name                   AS "Студент",
    email                       AS "Email",
    active_courses_count        AS "Активных курсов",
    TO_CHAR(registered_at, 'DD.MM.YYYY')
                                AS "Зарегистрирован",
    CASE
        WHEN last_activity_at IS NULL THEN 'Не входил'
        ELSE TO_CHAR(last_activity_at, 'DD.MM.YYYY HH24:MI')
    END                         AS "Последняя активность"
FROM school_edu.v_active_students
ORDER BY last_activity_at DESC NULLS LAST;


-- -------------------------------------------------------------
-- 3. СВОДКА ПО ВСЕМ КУРСАМ
-- -------------------------------------------------------------
-- 
-- >>> 3. КУРСЫ — СВОДНАЯ СТАТИСТИКА'
-- ------------------------------------------------------------'

SELECT
    topic                       AS "Тема",
    subject                     AS "Предмет",
    title                       AS "Курс",
    CASE WHEN is_active THEN 'Да' ELSE 'Нет' END
                                AS "Активен",
    modules                     AS "Модулей",
    lessons                     AS "Уроков",
    webinars                    AS "Вебинаров",
    homeworks                   AS "ДЗ",
    active_students             AS "Студентов",
    total_revenue               AS "Выручка (руб)",
    avg_completion_pct          AS "Ср. прогресс %"
FROM (
    WITH
    course_structure AS (
        SELECT c.id AS course_id,
            COUNT(DISTINCT m.id) AS modules_count,
            COUNT(DISTINCT l.id) FILTER (WHERE l.is_published) AS published_lessons,
            COUNT(DISTINCT l.id) FILTER (WHERE l.lesson_type='webinar' AND l.is_published) AS webinars_count,
            COUNT(DISTINCT hw.id) AS homeworks_count
        FROM school_edu.courses c
        LEFT JOIN school_edu.modules m ON m.course_id = c.id
        LEFT JOIN school_edu.lessons l ON l.module_id = m.id
        LEFT JOIN school_edu.homeworks hw ON hw.lesson_id = l.id
        GROUP BY c.id
    ),
    course_students AS (
        SELECT course_id,
            COUNT(*) FILTER (WHERE is_active) AS active_students
        FROM school_edu.enrollments GROUP BY course_id
    ),
    course_revenue AS (
        SELECT course_id, COALESCE(SUM(amount),0) AS total_revenue
        FROM school_fin.payments GROUP BY course_id
    ),
    course_progress AS (
        SELECT course_id, ROUND(AVG(completion_pct),1) AS avg_completion_pct
        FROM school_audit.mv_course_completion GROUP BY course_id
    )
    SELECT
        t.name                              AS topic,
        c.subject,
        c.title,
        c.is_active,
        COALESCE(cs.modules_count,0)        AS modules,
        COALESCE(cs.published_lessons,0)    AS lessons,
        COALESCE(cs.webinars_count,0)       AS webinars,
        COALESCE(cs.homeworks_count,0)      AS homeworks,
        COALESCE(cst.active_students,0)     AS active_students,
        COALESCE(cr.total_revenue,0)        AS total_revenue,
        COALESCE(cp.avg_completion_pct,0)   AS avg_completion_pct
    FROM school_edu.courses c
    JOIN school_edu.topics t ON t.id = c.topic_id
    LEFT JOIN course_structure cs  ON cs.course_id  = c.id
    LEFT JOIN course_students  cst ON cst.course_id = c.id
    LEFT JOIN course_revenue   cr  ON cr.course_id  = c.id
    LEFT JOIN course_progress  cp  ON cp.course_id  = c.id
) sub
ORDER BY total_revenue DESC;


-- -------------------------------------------------------------
-- 4. ПРОГРЕСС СТУДЕНТОВ ПО КУРСАМ
-- -------------------------------------------------------------
-- 
-- >>> 4. ПРОГРЕСС СТУДЕНТОВ'
-- ------------------------------------------------------------'

SELECT
    student_name                AS "Студент",
    course_title                AS "Курс",
    topic_name                  AS "Тема",
    completed_lessons || ' / ' || total_lessons
                                AS "Уроков пройдено",
    lessons_progress_pct        AS "Прогресс %",
    submitted_homeworks || ' / ' || total_homeworks
                                AS "ДЗ выполнено",
    total_score || ' / ' || max_possible_score
                                AS "Баллы",
    score_pct                   AS "Балл %"
FROM school_edu.v_student_progress
ORDER BY course_title, lessons_progress_pct DESC;


-- -------------------------------------------------------------
-- 5. РЕЙТИНГ СТУДЕНТОВ ПО БАЛЛАМ
-- -------------------------------------------------------------
-- 
-- >>> 5. РЕЙТИНГ СТУДЕНТОВ ПО БАЛЛАМ'
-- ------------------------------------------------------------'

SELECT
    rank_in_course              AS "Место",
    full_name                   AS "Студент",
    course_title                AS "Курс",
    total_score                 AS "Набрано баллов",
    max_possible_score          AS "Максимум",
    score_pct                   AS "Результат %"
FROM school_audit.mv_student_scores
ORDER BY course_title, rank_in_course;


-- -------------------------------------------------------------
-- 6. ФИНАНСЫ: ПЛАТЕЖИ ПО КУРСАМ
-- -------------------------------------------------------------
-- 
-- >>> 6. ФИНАНСЫ — ВЫРУЧКА ПО КУРСАМ'
-- ------------------------------------------------------------'

SELECT
    course_title                AS "Курс",
    topic_name                  AS "Тема",
    total_revenue               AS "Общая выручка",
    revenue_monthly             AS "Из них: помесячных",
    revenue_yearly              AS "Из них: годовых",
    payments_count              AS "Платежей",
    paying_students_count       AS "Платящих студентов",
    TO_CHAR(first_payment_date, 'DD.MM.YYYY')
                                AS "Первый платёж",
    TO_CHAR(last_payment_date,  'DD.MM.YYYY')
                                AS "Последний платёж"
FROM school_fin.v_course_finance
ORDER BY total_revenue DESC;


-- -------------------------------------------------------------
-- 7. БЛИЖАЙШИЕ ВЕБИНАРЫ
-- -------------------------------------------------------------
-- 
-- >>> 7. БЛИЖАЙШИЕ ВЕБИНАРЫ (30 дней)'
-- ------------------------------------------------------------'

SELECT
    TO_CHAR(webinar_scheduled_at, 'DD.MM.YYYY HH24:MI')
                                AS "Дата и время",
    lesson_title                AS "Тема вебинара",
    course_title                AS "Курс",
    duration_minutes            AS "Длит. (мин)",
    enrolled_count              AS "Участников",
    teachers                    AS "Преподаватель(и)"
FROM school_edu.v_upcoming_webinars
ORDER BY webinar_scheduled_at;


-- -------------------------------------------------------------
-- 8. ДЗ, ОЖИДАЮЩИЕ ПРОВЕРКИ
-- -------------------------------------------------------------
-- 
-- >>> 8. ДОМАШНИЕ ЗАДАНИЯ — ОЖИДАЮТ ПРОВЕРКИ'
-- ------------------------------------------------------------'

SELECT
    student_name                AS "Студент",
    course_title                AS "Курс",
    homework_title              AS "Домашнее задание",
    max_score                   AS "Макс. балл",
    TO_CHAR(submitted_at, 'DD.MM.YYYY HH24:MI')
                                AS "Сдано"
FROM school_edu.v_pending_homeworks
ORDER BY submitted_at;


-- -------------------------------------------------------------
-- 9. ЗАГРУЖЕННОСТЬ ПРЕПОДАВАТЕЛЕЙ
-- -------------------------------------------------------------
-- 
-- >>> 9. ЗАГРУЖЕННОСТЬ ПРЕПОДАВАТЕЛЕЙ'
-- ------------------------------------------------------------'

SELECT
    full_name                   AS "Преподаватель",
    courses_count               AS "Курсов",
    total_students              AS "Студентов",
    pending_checks              AS "ДЗ на проверке",
    total_checked               AS "Проверено всего"
FROM school_audit.mv_teacher_workload
ORDER BY total_students DESC;

