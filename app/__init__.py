from flask import Flask, redirect, url_for
from flask_login import LoginManager, current_user, login_required
from config import Config

login_manager = LoginManager()
login_manager.login_view = 'auth.login'
login_manager.login_message = "Пожалуйста, войдите в систему."
login_manager.login_message_category = "warning"

def create_app(config_class=Config):
    app = Flask(__name__)
    app.config.from_object(config_class)

    from app import db
    db.init_app(app)

    login_manager.init_app(app)

    from app.models import User
    @login_manager.user_loader
    def load_user(user_id):
        return User.get(user_id)

    # 1. Авторизация
    from app.routes.auth_routes import bp as auth_bp
    app.register_blueprint(auth_bp)

    # 2. Ученик
    from app.routes.student_routes import bp as student_bp
    app.register_blueprint(student_bp)

    # 3. Преподаватель (ИМЕННО ЭТОТ БЛОК РЕШАЕТ ВАШУ ОШИБКУ)
    from app.routes.teacher_routes import bp as teacher_bp
    app.register_blueprint(teacher_bp)

    # Распределитель (перенаправляет в кабинеты)
    @app.route('/')
    @login_required
    def index():
        if current_user.role == 'student':
            return redirect(url_for('student.dashboard'))
        elif current_user.role == 'teacher':
            return redirect(url_for('teacher.dashboard'))
        elif current_user.role == 'admin':
            return "<h1>Кабинет администратора (В разработке)</h1> <a href='/logout'>Выйти</a>"
        else:
            return redirect(url_for('auth.logout'))

    @app.route('/ping')
    def ping():
        return "Pong!"

    return app
