from flask import Blueprint, render_template, request, redirect, url_for, flash
from flask_login import login_required, current_user
from src.db import get_db
from src.decorators import role_required

bp = Blueprint('admin', __name__, url_prefix='/admin')

@bp.route('/dashboard')
@login_required
@role_required('admin')
def dashboard():
    """Главная сводка администратора с данными для графиков"""
    conn = get_db()
    cur = conn.cursor()
    try:
        # 1. Базовые метрики (карточки)
        cur.execute("SELECT count(*) as cnt FROM school_core.users WHERE role='student' AND is_active=true")
        total_students = cur.fetchone()['cnt']
        
        cur.execute("SELECT count(*) as cnt FROM school_core.users WHERE role='teacher' AND is_active=true")
        total_teachers = cur.fetchone()['cnt']
        
        cur.execute("SELECT count(*) as cnt FROM school_edu.courses")
        total_courses = cur.fetchone()['cnt']
        
        cur.execute("SELECT COALESCE(sum(amount), 0) as total FROM school_fin.payments")
        total_revenue = cur.fetchone()['total']

        # 2. Данные для круговой диаграммы (Пользователи по ролям)
        cur.execute("SELECT role, count(*) as cnt FROM school_core.users GROUP BY role")
        roles_data = cur.fetchall()
        roles_labels = [row['role'].capitalize() for row in roles_data]
        roles_counts = [row['cnt'] for row in roles_data]

        # 3. Данные для столбчатой диаграммы (Выручка за последние 6 месяцев)
        cur.execute("""
            SELECT TO_CHAR(DATE_TRUNC('month', payment_date), 'YYYY-MM') as month_label,
                   COALESCE(SUM(amount), 0) as revenue
            FROM school_fin.payments
            GROUP BY 1 
            ORDER BY 1 DESC 
            LIMIT 6
        """)
        rev_data = cur.fetchall()
        rev_data.reverse() # Разворачиваем, чтобы старые месяцы были слева, а новые справа
        rev_labels = [row['month_label'] for row in rev_data]
        rev_values = [row['revenue'] for row in rev_data]

        return render_template('admin/dashboard.html', 
                               stats={
                                   'total_students': total_students,
                                   'total_teachers': total_teachers,
                                   'total_courses': total_courses,
                                   'total_revenue': total_revenue
                               },
                               chart_roles={'labels': roles_labels, 'data': roles_counts},
                               chart_revenue={'labels': rev_labels, 'data': rev_values}
                               )
    finally:
        cur.close()

@bp.route('/finance')
@login_required
@role_required('admin')
def finance():
    """Финансовый отчет"""
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("""
            SELECT 
                TO_CHAR(DATE_TRUNC('month', payment_date), 'YYYY-MM') as month_label,
                COUNT(*) as payments_count,
                COUNT(DISTINCT student_id) as paying_students,
                COALESCE(SUM(amount), 0) as revenue
            FROM school_fin.payments
            GROUP BY DATE_TRUNC('month', payment_date)
            ORDER BY month_label DESC
        """)
        finance_data = cur.fetchall()
        return render_template('admin/finance.html', finance_data=finance_data)
    finally:
        cur.close()

@bp.route('/users', methods=['GET', 'POST'])
@login_required
@role_required('admin')
def users():
    """Управление пользователями"""
    conn = get_db()
    cur = conn.cursor()
    try:
        if request.method == 'POST':
            action = request.form.get('action')
            user_id = request.form.get('user_id')
            
            if action == 'deactivate':
                try:
                    cur.execute("CALL school_edu.pr_deactivate_student(%s, %s, %s)", 
                               (user_id, current_user.id, 'Деактивирован из ПУ'))
                    conn.commit()
                    flash('Пользователь успешно деактивирован!', 'success')
                except Exception as e:
                    conn.rollback()
                    flash(f'Ошибка деактивации: {str(e)}', 'danger')
            return redirect(url_for('admin.users'))

        cur.execute("""
            SELECT id, first_name, last_name, email, role, is_active, TO_CHAR(created_at, 'DD.MM.YYYY') as created
            FROM school_core.users 
            ORDER BY role, created_at DESC
        """)
        users_list = cur.fetchall()
        return render_template('admin/users.html', users=users_list)
    finally:
        cur.close()

@bp.route('/enroll', methods=['GET', 'POST'])
@login_required
@role_required('admin')
def enroll():
    """Управление зачислениями"""
    conn = get_db()
    cur = conn.cursor()
    try:
        if request.method == 'POST':
            student_id = request.form.get('student_id')
            course_id = request.form.get('course_id')
            
            try:
                cur.execute("CALL school_edu.pr_enroll_student(%s, %s, %s)",
                           (student_id, course_id, current_user.id))
                conn.commit()
                flash('Студент успешно зачислен на курс!', 'success')
            except Exception as e:
                conn.rollback()
                flash(f'Ошибка зачисления (возможно студент уже на курсе): {str(e)}', 'danger')
            return redirect(url_for('admin.enroll'))

        cur.execute("SELECT id, first_name, last_name, email FROM school_core.users WHERE role='student' AND is_active=true")
        students = cur.fetchall()
        
        cur.execute("SELECT id, title FROM school_edu.courses")
        courses = cur.fetchall()
        
        return render_template('admin/enroll.html', students=students, courses=courses)
    finally:
        cur.close()