#!/usr/bin/env python3
"""
Скрипт для тестирования подключения к PostgreSQL
"""
import os
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

# Загружаем переменные из .env
load_dotenv()

def test_db_connection():
    # Чтение параметров подключения
    DB_HOST = os.getenv("DB_HOST", "localhost")
    DB_PORT = os.getenv("DB_PORT", "5432")
    DB_USER = os.getenv("DB_USER", "postgres")
    DB_PASSWORD = os.getenv("DB_PASSWORD", "")
    DB_NAME = os.getenv("DB_NAME", "postgres")
    
    DATABASE_URL = f"postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
    
    print("=== Тест подключения к PostgreSQL ===")
    print(f"Хост: {DB_HOST}:{DB_PORT}")
    print(f"Пользователь: {DB_USER}")
    print(f"База данных: {DB_NAME}")
    print(f"Строка подключения: postgresql://{DB_USER}:***@{DB_HOST}:{DB_PORT}/{DB_NAME}")
    print()
    
    try:
        print("Создание движка SQLAlchemy...")
        engine = create_engine(DATABASE_URL, echo=False)
        
        print("Подключение к базе данных...")
        with engine.connect() as connection:
            # Тест 1: Версия PostgreSQL
            result = connection.execute(text("SELECT version();"))
            version = result.fetchone()
            print(f"✅ Версия PostgreSQL: {version[0][:50]}...")
            
            # Тест 2: Текущее время
            result = connection.execute(text("SELECT now();"))
            now = result.fetchone()
            print(f"✅ Текущее время на сервере: {now[0]}")
            
            # Тест 3: Список таблиц
            result = connection.execute(text("""
                SELECT table_name 
                FROM information_schema.tables 
                WHERE table_schema = 'public'
                ORDER BY table_name;
            """))
            tables = result.fetchall()
            print(f"✅ Таблицы в базе данных ({len(tables)}):")
            for table in tables:
                print(f"   - {table[0]}")
        
        print("\n🎉 Подключение успешно! Ваш бэкенд готов к работе с PostgreSQL.")
        return True
        
    except Exception as e:
        print(f"❌ Ошибка подключения: {e}")
        print("\n💡 Возможные решения:")
        print("1. Проверьте пароль в файле .env")
        print("2. Убедитесь, что PostgreSQL запущен")
        print("3. Проверьте имя базы данных")
        print("4. Проверьте настройки доступа в pg_hba.conf")
        return False

if __name__ == "__main__":
    test_db_connection()