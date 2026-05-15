-- =============================================================
-- ОНЛАЙН-ШКОЛА: 04_report_finance.sql
-- Финансовый отчёт для администратора
-- Запускать ПОСЛЕ 01_setup.sql и 02_test_data.sql
-- =============================================================

--
--============================================================'
--   ФИНАНСОВЫЙ ОТЧЁТ'
--============================================================'


-- -------------------------------------------------------------
-- 1. ЕЖЕМЕСЯЧНАЯ ДИНАМИКА ДОХОДОВ
-- -------------------------------------------------------------
--
-->>> 1. ДОХОДЫ ПО МЕСЯЦАМ (с динамикой)'
--------------------------------------------------------------'

WITH monthly_raw AS (
    SELECT
        DATE_TRUNC('month', payment_date)::DATE     AS month,
        TO_CHAR(DATE_TRUNC('month', payment_date), 'YYYY-MM') AS month_label,
        COALESCE(SUM(amount), 0)                    AS revenue,
        COALESCE(SUM(amount) FILTER (
            WHERE subscription_type = 'monthly'), 0) AS rev_monthly_sub,
        COALESCE(SUM(amount) FILTER (
            WHERE subscription_type = 'yearly'),  0) AS rev_yearly_sub,
        COUNT(DISTINCT student_id)                  AS paying_students,
        COUNT(*)                                    AS payments_count
    FROM school_fin.payments
    GROUP BY DATE_TRUNC('month', payment_date)
)
SELECT
    month_label                 AS "Месяц",
    revenue                     AS "Выручка (руб)",
    rev_monthly_sub             AS "Помесячные",
    rev_yearly_sub              AS "Годовые",
    paying_students             AS "Плательщиков",
    payments_count              AS "Платежей",
    COALESCE(
        revenue - LAG(revenue) OVER (ORDER BY month), 0
    )                           AS "Прирост (руб)",
    COALESCE(
        ROUND(
            (revenue - LAG(revenue) OVER (ORDER BY month))
            / NULLIF(LAG(revenue) OVER (ORDER BY month), 0) * 100, 1
        ), 0
    )                           AS "Прирост %",
    SUM(revenue) OVER (
        ORDER BY month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                           AS "Нарастающий итог"
FROM monthly_raw
ORDER BY month;


-- -------------------------------------------------------------
-- 2. ВЫРУЧКА ПО КУРСАМ С ABC-АНАЛИЗОМ
-- -------------------------------------------------------------
--
-->>> 2. ВЫРУЧКА ПО КУРСАМ (ABC-анализ)'
--------------------------------------------------------------'

WITH course_rev AS (
    SELECT
        p.course_id,
        c.title                                     AS course_title,
        c.subject,
        t.name                                      AS topic_name,
        SUM(p.amount)                               AS revenue,
        COUNT(DISTINCT p.student_id)                AS paying_students,
        COUNT(*)                                    AS payments_count
    FROM school_fin.payments    p
    JOIN school_edu.courses      c ON c.id  = p.course_id
    JOIN school_edu.topics       t ON t.id  = c.topic_id
    GROUP BY p.course_id, c.title, c.subject, t.name
)
SELECT
    RANK() OVER (ORDER BY revenue DESC)             AS "Ранг",
    topic_name                                      AS "Тема",
    course_title                                    AS "Курс",
    revenue                                         AS "Выручка (руб)",
    paying_students                                 AS "Студентов",
    payments_count                                  AS "Платежей",
    ROUND(revenue / SUM(revenue) OVER () * 100, 1)  AS "Доля %",
    ROUND(
        SUM(revenue) OVER (
            ORDER BY revenue DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / SUM(revenue) OVER () * 100, 1
    )                                               AS "Накопл. доля %",
    CASE
        WHEN SUM(revenue) OVER (
            ORDER BY revenue DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / SUM(revenue) OVER () <= 0.8             THEN 'A — приоритет'
        WHEN SUM(revenue) OVER (
            ORDER BY revenue DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / SUM(revenue) OVER () <= 0.95            THEN 'B — важные'
        ELSE                                             'C — прочие'
    END                                             AS "ABC-категория"
FROM course_rev
ORDER BY revenue DESC;


-- -------------------------------------------------------------
-- 3. СТУДЕНТЫ С ИСТЕКАЮЩЕЙ ПОДПИСКОЙ (ближайшие 30 дней)
-- -------------------------------------------------------------
--
-->>> 3. ИСТЕКАЮЩИЕ ПОДПИСКИ (30 дней)'
--------------------------------------------------------------'

WITH latest_payment AS (
    SELECT DISTINCT ON (student_id, course_id)
        student_id, course_id, amount,
        subscription_type, period_end, payment_date
    FROM school_fin.payments
    ORDER BY student_id, course_id, period_end DESC
)
SELECT
    school_core.fn_get_user_full_name(lp.student_id)
                                AS "Студент",
    u.email                     AS "Email",
    u.phone                     AS "Телефон",
    c.title                     AS "Курс",
    lp.subscription_type        AS "Тип подписки",
    lp.amount                   AS "Сумма (руб)",
    TO_CHAR(lp.period_end, 'DD.MM.YYYY')
                                AS "Истекает",
    (lp.period_end - CURRENT_DATE)
                                AS "Дней осталось",
    CASE
        WHEN lp.period_end < CURRENT_DATE
            THEN '🔴 Истёк'
        WHEN lp.period_end < CURRENT_DATE + 7
            THEN '🟠 Срочно (< 7 дней)'
        ELSE '🟡 В этом месяце'
    END                         AS "Статус"
FROM latest_payment              lp
JOIN school_core.users            u ON u.id         = lp.student_id
JOIN school_edu.courses           c ON c.id         = lp.course_id
JOIN school_edu.enrollments       e ON e.student_id = lp.student_id
                                   AND e.course_id  = lp.course_id
WHERE e.is_active = TRUE
  AND lp.period_end < CURRENT_DATE + INTERVAL '30 days'
ORDER BY lp.period_end ASC;


-- -------------------------------------------------------------
-- 4. СВОДНЫЙ ФИНАНСОВЫЙ ИТОГ
-- -------------------------------------------------------------
--
-->>> 4. ИТОГОВЫЕ ПОКАЗАТЕЛИ'
--------------------------------------------------------------'

SELECT
    COUNT(DISTINCT student_id)          AS "Всего платящих студентов",
    COUNT(DISTINCT course_id)           AS "Курсов с платежами",
    COUNT(*)                            AS "Всего платежей",
    SUM(amount)                         AS "Общая выручка (руб)",
    ROUND(AVG(amount), 2)               AS "Средний чек (руб)",
    MAX(amount)                         AS "Максимальный платёж",
    MIN(amount)                         AS "Минимальный платёж",
    COUNT(*) FILTER (
        WHERE subscription_type = 'yearly'
    )                                   AS "Годовых подписок",
    COUNT(*) FILTER (
        WHERE subscription_type = 'monthly'
    )                                   AS "Месячных подписок"
FROM school_fin.payments;


