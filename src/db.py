from flask import g
from src.extensions import db_pool

def get_db():
    """Возвращает соединение с базой данных из пула."""
    if 'db' not in g:
        # Извлекаем свободное соединение из пула
        g.db = db_pool.getconn()
    return g.db

def close_db(e=None):
    """Возвращает соединение обратно в пул после завершения запроса."""
    db = g.pop('db', None)
    if db is not None:
        db_pool.putconn(db)