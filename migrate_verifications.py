#!/usr/bin/env python3
"""
Миграция для обновления таблицы verifications под новую систему загрузки документов
"""
import os
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

# Загружаем переменные из .env
load_dotenv()

def migrate_verifications_table():
    # Чтение параметров подключения
    DB_HOST = os.getenv("DB_HOST", "localhost")
    DB_PORT = os.getenv("DB_PORT", "5432")
    DB_USER = os.getenv("DB_USER", "postgres")
    DB_PASSWORD = os.getenv("DB_PASSWORD", "")
    DB_NAME = os.getenv("DB_NAME", "postgres")
    
    DATABASE_URL = f"postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
    
    print("=== Миграция таблицы verifications ===")
    print(f"База данных: {DB_NAME}")
    
    try:
        engine = create_engine(DATABASE_URL, echo=True)
        
        with engine.connect() as connection:
            # Проверяем существование новых колонок
            check_columns = text("""
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name = 'verifications' 
                AND column_name IN ('document_type', 'selfie_url', 'notes');
            """)
            
            existing_columns = connection.execute(check_columns).fetchall()
            existing_column_names = [row[0] for row in existing_columns]
            
            print(f"Существующие колонки: {existing_column_names}")
            
            # Добавляем колонку document_type если её нет
            if 'document_type' not in existing_column_names:
                print("Добавляем колонку document_type...")
                connection.execute(text("""
                    ALTER TABLE verifications 
                    ADD COLUMN document_type VARCHAR(20) DEFAULT 'passport';
                """))
                print("✅ Колонка document_type добавлена")
            else:
                print("✅ Колонка document_type уже существует")
            
            # Добавляем колонку selfie_url если её нет
            if 'selfie_url' not in existing_column_names:
                print("Добавляем колонку selfie_url...")
                connection.execute(text("""
                    ALTER TABLE verifications 
                    ADD COLUMN selfie_url VARCHAR(255);
                """))
                
                # Для существующих записей устанавливаем значение по умолчанию
                connection.execute(text("""
                    UPDATE verifications 
                    SET selfie_url = 'uploads/selfies/placeholder.jpg' 
                    WHERE selfie_url IS NULL;
                """))
                
                # Делаем колонку обязательной
                connection.execute(text("""
                    ALTER TABLE verifications 
                    ALTER COLUMN selfie_url SET NOT NULL;
                """))
                
                print("✅ Колонка selfie_url добавлена")
            else:
                print("✅ Колонка selfie_url уже существует")
            
            # Добавляем колонку notes если её нет
            if 'notes' not in existing_column_names:
                print("Добавляем колонку notes...")
                connection.execute(text("""
                    ALTER TABLE verifications 
                    ADD COLUMN notes TEXT;
                """))
                print("✅ Колонка notes добавлена")
            else:
                print("✅ Колонка notes уже существует")
            
            # Обновляем существующие записи
            print("Обновляем значения по умолчанию для существующих записей...")
            connection.execute(text("""
                UPDATE verifications 
                SET document_type = 'passport' 
                WHERE document_type IS NULL;
            """))
            
            connection.commit()
            print("\n🎉 Миграция verifications успешно завершена!")
            print("Теперь система поддерживает загрузку документов и селфи для верификации")
            
    except Exception as e:
        print(f"❌ Ошибка миграции: {e}")
        return False
    
    return True

if __name__ == "__main__":
    migrate_verifications_table()