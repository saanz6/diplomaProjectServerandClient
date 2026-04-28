#!/usr/bin/env python3
"""
Миграция для добавления owner_id в таблицу properties
"""
import os
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

load_dotenv()


def migrate_properties_owner():
    DB_HOST = os.getenv("DB_HOST", "localhost")
    DB_PORT = os.getenv("DB_PORT", "5432")
    DB_USER = os.getenv("DB_USER", "postgres")
    DB_PASSWORD = os.getenv("DB_PASSWORD", "")
    DB_NAME = os.getenv("DB_NAME", "postgres")

    DATABASE_URL = f"postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

    print("=== Миграция owner_id в properties ===")
    print(f"База данных: {DB_NAME}")

    try:
        engine = create_engine(DATABASE_URL, echo=True)

        with engine.connect() as connection:
            check_column = text("""
                SELECT column_name
                FROM information_schema.columns
                WHERE table_name = 'properties'
                AND column_name = 'owner_id';
            """)

            exists = connection.execute(check_column).fetchone()

            if not exists:
                print("Добавляем колонку owner_id...")
                connection.execute(text("""
                    ALTER TABLE properties
                    ADD COLUMN owner_id INTEGER;
                """))

                print("Добавляем внешний ключ properties.owner_id -> users.id...")
                connection.execute(text("""
                    ALTER TABLE properties
                    ADD CONSTRAINT fk_properties_owner_id
                    FOREIGN KEY (owner_id) REFERENCES users(id)
                    ON DELETE SET NULL;
                """))

                print("Добавляем индекс idx_properties_owner_id...")
                connection.execute(text("""
                    CREATE INDEX idx_properties_owner_id ON properties(owner_id);
                """))
                print("✅ owner_id добавлен")
            else:
                print("✅ Колонка owner_id уже существует")

            connection.commit()
            print("\n🎉 Миграция успешно завершена")

    except Exception as e:
        print(f"❌ Ошибка миграции: {e}")
        return False

    return True


if __name__ == "__main__":
    migrate_properties_owner()
