from flask import Blueprint, render_template, request, redirect, url_for, flash
from flask_login import login_required, current_user
from app.db import get_db
from app.decorators import role_required

bp = Blueprint('student', __name__, url_prefix='/student')

@bp.route('/dashboard')
@login_required
@role_required('student')
def dashboard():
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("""
            SELECT course_id, course_title, subject, topic_name, 
                   completed_lessons, total_lessons, lessons_progress_pct,
                   submitted_homeworks, total_homeworks, score_pct
            FROM school_edu.v_student_progress
            WHERE student_id = %s AND enrollment_active = TRUE
            ORDER BY lessons_progress_pct DESC;
        """, (current_user.id,))
        courses = cur.fetchall()
        return render_template('student/dashboard.html', courses=courses)
    finally:
        cur.close()

@bp.route('/course/<string:course_id>')
@login_required
@role_required('student')
def course_view(course_id):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT school_edu.fn_is_student_enrolled(%s, %s) as is_enrolled", (current_user.id, course_id))
        if not cur.fetchone()['is_enrolled']:
            flash('У вас нет доступа к этому курсу.', 'danger')
            return redirect(url_for('student.dashboard'))

        cur.execute("SELECT title FROM school_edu.courses WHERE id = %s", (course_id,))
        course_title = cur.fetchone()['title']

        cur.execute("""
            SELECT m.id as module_id, m.title as module_title, 
                   l.id as lesson_id, l.title as lesson_title, l.lesson_type, l.duration_minutes,
                   COALESCE(lp.is_completed, FALSE) as is_completed
            FROM school_edu.modules m
            JOIN school_edu.lessons l ON l.module_id = m.id
            LEFT JOIN school_edu.lesson_progress lp 
                   ON lp.lesson_id = l.id AND lp.student_id = %s
            WHERE m.course_id = %s AND l.is_published = TRUE
            ORDER BY m.order_index, l.order_index;
        """, (current_user.id, course_id))
        
        modules = {}
        for row in cur.fetchall():
            m_id = row['module_id']
            if m_id not in modules:
                modules[m_id] = {'title': row['module_title'], 'lessons': []}
            modules[m_id]['lessons'].append(row)

        return render_template('student/course_view.html', modules=modules.values(), course_title=course_title, course_id=course_id)
    finally:
        cur.close()

@bp.route('/lesson/<string:lesson_id>', methods=['GET', 'POST'])
@login_required
@role_required('student')
def lesson_view(lesson_id):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("""
            SELECT l.*, m.course_id, c.title as course_title, COALESCE(lp.is_completed, FALSE) as is_completed
            FROM school_edu.lessons l
            JOIN school_edu.modules m ON m.id = l.module_id
            JOIN school_edu.courses c ON c.id = m.course_id
            LEFT JOIN school_edu.lesson_progress lp ON lp.lesson_id = l.id AND lp.student_id = %s
            WHERE l.id = %s;
        """, (current_user.id, lesson_id))
        lesson = cur.fetchone()

        if not lesson:
            flash('Урок не найден.', 'danger')
            return redirect(url_for('student.dashboard'))

        cur.execute("SELECT school_edu.fn_is_student_enrolled(%s, %s) as is_enrolled", (current_user.id, lesson['course_id']))
        if not cur.fetchone()['is_enrolled']:
            flash('Доступ запрещен.', 'danger')
            return redirect(url_for('student.dashboard'))

        if request.method == 'POST':
            action = request.form.get('action')
            
            if action == 'complete_lesson':
                cur.execute("""
                    INSERT INTO school_edu.lesson_progress (student_id, lesson_id, is_completed)
                    VALUES (%s, %s, TRUE)
                    ON CONFLICT (student_id, lesson_id) 
                    DO UPDATE SET is_completed = TRUE;
                """, (current_user.id, lesson_id))
                conn.commit()
                flash('Урок отмечен как пройденный!', 'success')
                return redirect(url_for('student.lesson_view', lesson_id=lesson_id))
            
            elif action == 'submit_hw':
                hw_id = request.form.get('homework_id')
                answer_text = request.form.get('answer_text')
                answer_url = request.form.get('answer_url')
                
                if not answer_text and not answer_url:
                    flash('Необходимо заполнить текст ответа или прикрепить ссылку.', 'warning')
                else:
                    try:
                        cur.execute("""
                            INSERT INTO school_edu.homework_submissions (homework_id, student_id, answer_text, answer_url, status)
                            VALUES (%s, %s, %s, %s, 'submitted')
                        """, (hw_id, current_user.id, answer_text or None, answer_url or None))
                        conn.commit()
                        flash('Домашнее задание успешно отправлено!', 'success')
                    except Exception as e:
                        conn.rollback()
                        flash(f'Ошибка отправки: {str(e)}', 'danger')
                return redirect(url_for('student.lesson_view', lesson_id=lesson_id))

        cur.execute("""
            SELECT hw.*, hs.status, hs.score, hs.answer_text, hs.answer_url, hs.checked_at
            FROM school_edu.homeworks hw
            LEFT JOIN school_edu.homework_submissions hs 
                   ON hs.homework_id = hw.id AND hs.student_id = %s
            WHERE hw.lesson_id = %s;
        """, (current_user.id, lesson_id))
        homeworks = cur.fetchall()

        return render_template('student/lesson_view.html', lesson=lesson, homeworks=homeworks)
    finally:
        cur.close()
