from functools import wraps
from flask import redirect, url_for, flash
from flask_login import current_user

def role_required(*roles):
    """
    Декоратор для ограничения доступа. 
    Если роль не совпадает, перенаправляет в нужный кабинет с сообщением.
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            if not current_user.is_authenticated:
                flash('Пожалуйста, авторизуйтесь.', 'warning')
                return redirect(url_for('auth.login'))
                
            if current_user.role not in roles:
                # Если ученик лезет к админу (или наоборот) — выдаем ошибку
                flash('У вас нет прав для доступа к этой странице.', 'danger')
                
                # Мягко возвращаем пользователя в ЕГО кабинет
                if current_user.role == 'student':
                    return redirect(url_for('student.dashboard'))
                elif current_user.role == 'teacher':
                    return redirect(url_for('teacher.dashboard'))
                elif current_user.role == 'admin':
                    return redirect(url_for('admin.dashboard'))
                else:
                    return redirect(url_for('auth.logout'))
                    
            return f(*args, **kwargs)
        return decorated_function
    return decorator
