from flask_login import UserMixin
from app.db import get_db

class User(UserMixin):
    def __init__(self, id, role, first_name):
        self.id = str(id)
        self.role = role
        self.first_name = first_name

    @staticmethod
    def get(user_id):
        conn = get_db()
        cur = conn.cursor()
        try:
            cur.execute("""
                SELECT id, role, first_name 
                FROM school_core.users 
                WHERE id = %s AND is_active = TRUE;
            """, (user_id,))
            user_data = cur.fetchone()
            if user_data:
                return User(id=user_data['id'], role=user_data['role'], first_name=user_data['first_name'])
        finally:
            cur.close()
        return None

    @staticmethod
    def authenticate(email, password):
        conn = get_db()
        cur = conn.cursor()
        try:
            cur.execute("""
                SELECT id, role, first_name 
                FROM school_core.users 
                WHERE email = %s 
                  AND password_hash = crypt(%s, password_hash) 
                  AND is_active = TRUE;
            """, (email, password))
            user_data = cur.fetchone()
            
            if user_data:
                return User(id=user_data['id'], role=user_data['role'], first_name=user_data['first_name'])
        finally:
            cur.close()
        return None
