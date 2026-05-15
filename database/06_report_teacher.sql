--============================================================'
--   КАБИНЕТ ПРЕПОДАВАТЕЛЯ'
--============================================================'


-- -------------------------------------------------------------
-- 1. МОИ СТУДЕНТЫ (Иванова — ЕГЭ Математика)
-- -------------------------------------------------------------

-->>> 1. СТУДЕНТЫ ПРЕПОДАВАТЕЛЯ: Иванова М.А.'
--   (функция fn_get_teacher_students)'
--------------------------------------------------------------'

SELECT
    full_name                   AS "Студент",
    email                       AS "Email",
    course_title                AS "Курс",
    TO_CHAR(enrolled_at, 'DD.MM.YYYY')
                                AS "Зачислен",
    total_score                 AS "Баллов набрано",
    completed_pct               AS "Прогресс %"
FROM school_edu.fn_get_teacher_students(
    '00000000-0000-0000-0000-000000000010'  -- Иванова
)
ORDER BY course_title, completed_pct DESC;


-- -------------------------------------------------------------
-- 2. ДЗ, ОЖИДАЮЩИЕ ПРОВЕРКИ (все преподаватели)
-- -------------------------------------------------------------

-->>> 2. ДОМАШНИЕ ЗАДАНИЯ — ОЧЕРЕДЬ ПРОВЕРКИ'
--------------------------------------------------------------'

WITH pending AS (
    SELECT
        hs.id                   AS submission_id,
        hs.submitted_at,
        hs.student_id,
        hw.title                AS homework_title,
        hw.max_score,
        hw.deadline_hours,
        l.title                 AS lesson_title,
        m.title                 AS module_title,
        c.title                 AS course_title,
        CASE
            WHEN hw.deadline_hours IS NOT NULL
            THEN hs.submitted_at + (hw.deadline_hours || ' hours')::INTERVAL
        END                     AS check_deadline,
        ARRAY_AGG(DISTINCT ct.teacher_id) AS teacher_ids
    FROM school_edu.homework_submissions  hs
    JOIN school_edu.homeworks             hw  ON hw.id        = hs.homework_id
    JOIN school_edu.lessons               l   ON l.id         = hw.lesson_id
    JOIN school_edu.modules               m   ON m.id         = l.module_id
    JOIN school_edu.courses               c   ON c.id         = m.course_id
    LEFT JOIN school_edu.course_teachers  ct  ON ct.course_id = c.id
    WHERE hs.status     = 'submitted'
      AND hw.check_type = 'manual'
    GROUP BY hs.id, hs.submitted_at, hs.student_id,
             hw.title, hw.max_score, hw.deadline_hours,
             l.title, m.title, c.title
)
SELECT
    school_core.fn_get_user_full_name(student_id)
                                AS "Студент",
    course_title                AS "Курс",
    module_title                AS "Модуль",
    homework_title              AS "Задание",
    max_score                   AS "Макс. балл",
    TO_CHAR(submitted_at, 'DD.MM.YYYY HH24:MI')
                                AS "Сдано",
    ROUND(
        EXTRACT(EPOCH FROM NOW() - submitted_at) / 3600, 1
    )                           AS "Ждёт (часов)",
    CASE
        WHEN check_deadline IS NULL             THEN 'Без дедлайна'
        WHEN NOW() > check_deadline             THEN '🔴 Просрочено'
        WHEN NOW() > check_deadline - INTERVAL '2 hours'
                                                THEN '🟠 Срочно'
        ELSE                                         '🟢 В срок'
    END                         AS "Дедлайн"
FROM pending
ORDER BY submitted_at ASC;


-- -------------------------------------------------------------
-- 3. ЗАГРУЖЕННОСТЬ ВСЕХ ПРЕПОДАВАТЕЛЕЙ
-- -------------------------------------------------------------
--
-->>> 3. ЗАГРУЖЕННОСТЬ ПРЕПОДАВАТЕЛЕЙ'
-- ------------------------------------------------------------'

SELECT
    full_name                   AS "Преподаватель",
    email                       AS "Email",
    courses_count               AS "Курсов",
    courses_count               AS "Активных",
    total_students              AS "Студентов",
    pending_checks              AS "ДЗ на проверке",
    total_checked               AS "Проверено за всё время",
    RANK() OVER (ORDER BY total_students DESC)
                                AS "Ранг по студентам"
FROM school_audit.mv_teacher_workload
ORDER BY total_students DESC;


-- -------------------------------------------------------------
-- 4. БЛИЖАЙШИЕ ВЕБИНАРЫ ПРЕПОДАВАТЕЛЯ (Смирнов)
-- -------------------------------------------------------------
--
-->>> 4. БЛИЖАЙШИЕ ВЕБИНАРЫ: Смирнов А.В.'
--------------------------------------------------------------'

SELECT
    TO_CHAR(webinar_scheduled_at, 'DD.MM.YYYY HH24:MI')
                                AS "Дата и время",
    lesson_title                AS "Тема",
    course_title                AS "Курс",
    duration_minutes            AS "Длит. (мин)",
    enrolled_count              AS "Студентов"
FROM school_edu.v_upcoming_webinars
WHERE teachers    ILIKE '%Смирнов%'
ORDER BY webinar_scheduled_at;


-- -------------------------------------------------------------
-- 5. ПРИМЕР: преподаватель проверяет ДЗ через процедуру
-- -------------------------------------------------------------

-->>> 5. ПРОВЕРКА ДЗ ПРЕПОДАВАТЕЛЕМ (pr_check_homework)'
--   Смирнов проверяет работу Новикова по производным'
--------------------------------------------------------------'

DO $$
DECLARE
    v_submission_id UUID;
BEGIN
    -- Находим сдачу Новикова (ДЗ на производные)
    SELECT hs.id INTO v_submission_id
    FROM school_edu.homework_submissions  hs
    JOIN school_edu.homeworks             hw ON hw.id = hs.homework_id
    WHERE hs.student_id  = '00000000-0000-0000-0000-000000000021'
      AND hw.check_type  = 'manual'
      AND hs.status      = 'submitted'
    LIMIT 1;

    IF v_submission_id IS NOT NULL THEN
        CALL school_edu.pr_check_homework(
            v_submission_id,
            '00000000-0000-0000-0000-000000000011',  -- Смирнов
            17::SMALLINT,
            'Хорошая работа! Задачи 1-4 решены верно, в задаче 5 небольшая ошибка.'
        );
        RAISE NOTICE 'ДЗ проверено, submission_id=%', v_submission_id;
    ELSE
        RAISE NOTICE 'Нет ДЗ на проверке для данного студента.';
    END IF;
END;
$$;

-- Показываем результат после проверки
--
--   Результат после проверки:'

SELECT
    school_core.fn_get_user_full_name(hs.student_id)
                                AS "Студент",
    hw.title                    AS "Задание",
    hw.max_score                AS "Макс. балл",
    hs.score                    AS "Балл",
    CASE hs.status
        WHEN 'checked'      THEN '🟢 Проверено'
        WHEN 'submitted'    THEN '🟡 Ожидает'
        WHEN 'auto_checked' THEN '🔵 Авто'
    END                         AS "Статус",	
    CASE
        WHEN hs.checked_by IS NOT NULL
        THEN school_core.fn_get_user_full_name(hs.checked_by)
        ELSE 'Автопроверка'
    END                         AS "Проверил",
    TO_CHAR(hs.checked_at, 'DD.MM.YYYY HH24:MI')
                                AS "Время проверки"
FROM school_edu.homework_submissions  hs
JOIN school_edu.homeworks             hw ON hw.id = hs.homework_id
WHERE hs.student_id = '00000000-0000-0000-0000-000000000021'
ORDER BY hs.submitted_at;



