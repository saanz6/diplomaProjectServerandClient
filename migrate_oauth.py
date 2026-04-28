#!/usr/bin/env python3
"""
Скрипт миграции для добавления OAuth поддержки в таблицу users
"""
import os
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

# Загружаем переменные из .env
load_dotenv()

def migrate_database():
    # Чтение параметров подключения
    DB_HOST = os.getenv("DB_HOST", "localhost")
    DB_PORT = os.getenv("DB_PORT", "5432")
    DB_USER = os.getenv("DB_USER", "postgres")
    DB_PASSWORD = os.getenv("DB_PASSWORD", "")
    DB_NAME = os.getenv("DB_NAME", "postgres")
    
    DATABASE_URL = f"postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
    
    print("=== Миграция базы данных для OAuth ===")
    print(f"База данных: {DB_NAME}")
    
    try:
        engine = create_engine(DATABASE_URL, echo=True)
        
        with engine.connect() as connection:
            # Проверяем существование колонок
            check_columns = text("""
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name = 'users' 
                AND column_name IN ('auth_provider', 'google_id');
            """)
            
            existing_columns = connection.execute(check_columns).fetchall()
            existing_column_names = [row[0] for row in existing_columns]
            
            print(f"Существующие OAuth колонки: {existing_column_names}")
            
            # Добавляем колонку auth_provider если её нет
            if 'auth_provider' not in existing_column_names:
                print("Добавляем колонку auth_provider...")
                connection.execute(text("""
                    ALTER TABLE users 
                    ADD COLUMN auth_provider VARCHAR(20) DEFAULT 'email';
                """))
                
                # Обновляем существующих пользователей
                connection.execute(text("""
                    UPDATE users 
                    SET auth_provider = 'email' 
                    WHERE auth_provider IS NULL;
                """))
                print("✅ Колонка auth_provider добавлена")
            else:
                print("✅ Колонка auth_provider уже существует")
            
            # Добавляем колонку google_id если её нет
            if 'google_id' not in existing_column_names:
                print("Добавляем колонку google_id...")
                connection.execute(text("""
                    ALTER TABLE users 
                    ADD COLUMN google_id VARCHAR(100) UNIQUE;
                """))
                print("✅ Колонка google_id добавлена")
            else:
                print("✅ Колонка google_id уже существует")
            
            # Делаем password_hash nullable для OAuth пользователей
            print("Обновляем колонку password_hash...")
            connection.execute(text("""
                ALTER TABLE users 
                ALTER COLUMN password_hash DROP NOT NULL;
            """))
            print("✅ Колонка password_hash теперь nullable")
            
            connection.commit()
            print("\n🎉 Миграция успешно завершена!")
            print("Теперь ваш сервер поддерживает OAuth аутентификацию через Google")
            
    except Exception as e:
        print(f"❌ Ошибка миграции: {e}")
        return False
    
    return True

if __name__ == "__main__":
    migrate_database()