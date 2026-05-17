import logging
from apscheduler.schedulers.background import BackgroundScheduler
from src.extensions import db_pool

logger = logging.getLogger(__name__)

def refresh_materialized_views():
    """Фоновая задача: Обновление всех материализованных представлений в БД."""
    if db_pool is None:
        return

    # Берем отдельное соединение для фонового потока
    conn = db_pool.getconn()
    try:
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute("SELECT school_audit.refresh_all_materialized_views();")
        logger.info("Материализованные представления (отчеты) успешно обновлены.")
    except Exception as e:
        logger.error(f"Ошибка при обновлении MV: {e}")
    finally:
        # Обязательно возвращаем соединение в пул
        conn.autocommit = False
        db_pool.putconn(conn)

def init_scheduler(app):
    """Инициализация планировщика задач."""
    scheduler = BackgroundScheduler()
    # Запуск задачи каждые 15 минут
    scheduler.add_job(func=refresh_materialized_views, trigger="interval", minutes=15)
    scheduler.start()
    return scheduler