# Online School Platform Backend (v1)

This repository contains the backend for the Online School Platform. It features a dual-framework setup with a Flask-based application for the web interface and a Django-based structure for potential management and API extensions.

## Project Structure

### 1. Flask Application (`app/`)
The primary web application logic is located in the `app/` directory:
- `app/routes/`: Contains blueprints for `admin`, `auth`, `student`, and `teacher` roles.
- `app/templates/`: Jinja2 templates for all user roles.
- `app/static/`: CSS and JS assets.
- `app/models.py`: User model and authentication logic using `psycopg2`.
- `app/db.py`: Database connection management.

### 2. Django Structure (`apps/` & `config/`)
A secondary structure designed for Django integration:
- `apps/`: Contains Django applications for `core`, `edu`, `fin`, and `analytics`.
- `config/`: Django project settings and root URL configuration.

### 3. Database Layer (`database/`)
The database uses PostgreSQL with a multi-schema architecture:
- `01_setup.sql`: Complete DDL (Schemas, Tables, Procedures, Triggers).
- `02_test_data.sql`: Comprehensive test data seeding.
- `03_report_admin_dashboard.sql` to `06_report_teacher.sql`: Reporting views and materialized views for different user roles.

## Getting Started

1. **Install Dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

2. **Database Setup:**
   Run the SQL scripts in the `database/` directory in numerical order against your PostgreSQL instance.

3. **Configuration:**
   Create a `.env` file based on the environment variables required in `config.py`.

4. **Run the Application:**
   ```bash
   python run.py
   ```

## Key Features
- **Role-Based Access Control:** Separate dashboards and routes for Admin, Teacher, and Student.
- **Database Driven Logic:** Business operations (enrollment, grading) are handled via stored procedures for consistency.
- **Rich Reporting:** Materialized views and complex queries provide real-time analytics for administration and teaching staff.
