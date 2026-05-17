from flask import Flask, redirect, url_for
from flask_login import LoginManager, current_user, login_required
from flask_wtf.csrf import CSRFProtect
from psycopg2.pool import ThreadedConnectionPool
from src.config import Config
import src.extensions as extensions

# Расширения
login_manager = LoginManager()
login_manager.login_view = 'auth.login'
login_manager.login_message = "Пожалуйста, войдите в систему."
login_manager.login_message_category = "warning"

csrf = CSRFProtect()

def create_app(config_class=Config):
    app = Flask(__name__, static_folder='static', template_folder='templates')
    app.config.from_object(config_class)

    # 1. Инициализация пула БД (Min: 1, Max: 20 соединений)
    extensions.db_pool = ThreadedConnectionPool(
        1, 20,
        host=app.config['DB_HOST'],
        port=app.config['DB_PORT'],
        dbname=app.config['DB_NAME'],
        user=app.config['DB_USER'],
        password=app.config['DB_PASSWORD']
    )

    # Регистрация хука для возврата соединения в пул в конце HTTP-запроса
    from src.db import close_db
    app.teardown_appcontext(close_db)

    # 2. Инициализация CSRF-защиты
    csrf.init_app(app)

    # 3. Инициализация сессий
    login_manager.init_app(app)

    from src.models import User
    @login_manager.user_loader
    def load_user(user_id):
        return User.get(user_id)

    # 4. Инициализация фоновых задач (Планировщик отчетов)
    from src.services.tasks import init_scheduler
    init_scheduler(app)

    # 5. Регистрация модулей (Blueprints)
    from src.routes.auth_routes import bp as auth_bp
    app.register_blueprint(auth_bp)

    from src.routes.student_routes import bp as student_bp
    app.register_blueprint(student_bp)

    from src.routes.teacher_routes import bp as teacher_bp
    app.register_blueprint(teacher_bp)

    from src.routes.admin_routes import bp as admin_bp
    app.register_blueprint(admin_bp)

    # 6. Базовые маршруты
    @app.route('/')
    @login_required
    def index():
        if current_user.role == 'student':
            return redirect(url_for('student.dashboard'))
        elif current_user.role == 'teacher':
            return redirect(url_for('teacher.dashboard'))
        elif current_user.role == 'admin':
            return redirect(url_for('admin.dashboard'))
        else:
            return redirect(url_for('auth.logout'))

    @app.route('/ping')
    def ping():
        return "Pong! Приложение работает безопасно."

    return app