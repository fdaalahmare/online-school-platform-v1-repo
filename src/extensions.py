from psycopg2.pool import ThreadedConnectionPool

# Глобальный пул соединений с базой данных
db_pool = None