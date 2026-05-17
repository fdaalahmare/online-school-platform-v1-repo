from flask import Flask, redirect, url_for
from flask_login import LoginManager, current_user, login_required
from src.config import Config

# Настройка менеджера авторизации
login_manager = LoginManager()
login_manager.login_view = 'auth.login'
login_manager.login_message = "Пожалуйста, войдите в систему."
login_manager.login_message_category = "warning"

def create_app(config_class=Config):
    # При переименовании папки app в src важно явно указать пути к статике и шаблонам
    app = Flask(__name__, static_folder='static', template_folder='templates')
    app.config.from_object(config_class)

    # 1. Подключение к БД
    from src import db
    db.init_app(app)

    # 2. Инициализация сессий
    login_manager.init_app(app)

    from src.models import User
    @login_manager.user_loader
    def load_user(user_id):
        return User.get(user_id)

    # 3. Регистрация всех модулей (Blueprints)
    
    # Авторизация
    from src.routes.auth_routes import bp as auth_bp
    app.register_blueprint(auth_bp)

    # Ученик
    from src.routes.student_routes import bp as student_bp
    app.register_blueprint(student_bp)

    # Преподаватель
    from src.routes.teacher_routes import bp as teacher_bp
    app.register_blueprint(teacher_bp)

    # Администратор (ДОБАВЛЕНО ДЛЯ ЭТАПА 5)
    from src.routes.admin_routes import bp as admin_bp
    app.register_blueprint(admin_bp)

    # 4. Маршрут-распределитель (Главная страница)
    @app.route('/')
    @login_required
    def index():
        # Перенаправляем пользователя в его кабинет в зависимости от роли
        if current_user.role == 'student':
            return redirect(url_for('student.dashboard'))
        elif current_user.role == 'teacher':
            return redirect(url_for('teacher.dashboard'))
        elif current_user.role == 'admin':
            return redirect(url_for('admin.dashboard'))
        else:
            return redirect(url_for('auth.logout'))

    # Тестовый маршрут для проверки работы сервера
    @app.route('/ping')
    def ping():
        return "Pong! Приложение работает."

    return app