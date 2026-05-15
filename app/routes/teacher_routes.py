from flask import Blueprint, render_template, request, redirect, url_for, flash
from flask_login import login_required, current_user
from app.db import get_db
from app.decorators import role_required

# Создаем Blueprint с префиксом /teacher (очень важно, чтобы имя было 'teacher')
bp = Blueprint('teacher', __name__, url_prefix='/teacher')

@bp.route('/dashboard')
@login_required
@role_required('teacher')
def dashboard():
    """Дашборд преподавателя со статистикой"""
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT count(*) FROM school_edu.fn_get_teacher_students(%s)", (current_user.id,))
        students_count = cur.fetchone()['count']

        cur.execute("""
            SELECT count(hs.id)
            FROM school_edu.homework_submissions hs
            JOIN school_edu.homeworks hw ON hw.id = hs.homework_id
            JOIN school_edu.lessons l ON l.id = hw.lesson_id
            JOIN school_edu.modules m ON m.id = l.module_id
            JOIN school_edu.courses c ON c.id = m.course_id
            WHERE hs.status = 'submitted' AND c.teacher_id = %s
        """, (current_user.id,))
        pending_hw_count = cur.fetchone()['count']

        return render_template('teacher/dashboard.html', 
                               students_count=students_count, 
                               pending_hw_count=pending_hw_count)
    finally:
        cur.close()

@bp.route('/students')
@login_required
@role_required('teacher')
def students():
    """Список всех студентов преподавателя"""
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("""
            SELECT full_name, email, course_title, 
                   TO_CHAR(enrolled_at, 'DD.MM.YYYY') as enrolled_date, 
                   total_score, completed_pct
            FROM school_edu.fn_get_teacher_students(%s)
            ORDER BY course_title, completed_pct DESC
        """, (current_user.id,))
        students_list = cur.fetchall()
        
        return render_template('teacher/students.html', students=students_list)
    finally:
        cur.close()

@bp.route('/homeworks', methods=['GET', 'POST'])
@login_required
@role_required('teacher')
def homeworks():
    """Проверка домашних заданий"""
    conn = get_db()
    cur = conn.cursor()
    try:
        if request.method == 'POST':
            submission_id = request.form.get('submission_id')
            score = request.form.get('score')
            comment = request.form.get('comment')
            
            try:
                cur.execute("CALL school_edu.pr_check_homework(%s, %s, %s, %s)", 
                            (submission_id, current_user.id, score, comment))
                conn.commit()
                flash('Оценка успешно сохранена!', 'success')
            except Exception as e:
                conn.rollback()
                flash(f'Ошибка при сохранении: {str(e)}', 'danger')
            return redirect(url_for('teacher.homeworks'))

        cur.execute("""
            SELECT
                hs.id as submission_id,
                TO_CHAR(hs.submitted_at, 'DD.MM.YYYY HH24:MI') as submitted_date,
                hw.title as homework_title,
                hw.max_score,
                hs.answer_text,
                hs.answer_url,
                c.title as course_title,
                u.first_name || ' ' || u.last_name as student_name
            FROM school_edu.homework_submissions hs
            JOIN school_edu.homeworks hw ON hw.id = hs.homework_id
            JOIN school_edu.lessons l ON l.id = hw.lesson_id
            JOIN school_edu.modules m ON m.id = l.module_id
            JOIN school_edu.courses c ON c.id = m.course_id
            JOIN school_core.users u ON u.id = hs.student_id
            WHERE hs.status = 'submitted' AND c.teacher_id = %s
            ORDER BY hs.submitted_at ASC;
        """, (current_user.id,))
        pending_hws = cur.fetchall()
        
        return render_template('teacher/homeworks.html', homeworks=pending_hws)
    finally:
        cur.close()
