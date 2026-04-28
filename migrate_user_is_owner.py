#!/usr/bin/env python3
"""
Миграция для добавления is_owner в таблицу users
"""
import os
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

load_dotenv()


def migrate_user_is_owner():
    DB_HOST = os.getenv("DB_HOST", "localhost")
    DB_PORT = os.getenv("DB_PORT", "5432")
    DB_USER = os.getenv("DB_USER", "postgres")
    DB_PASSWORD = os.getenv("DB_PASSWORD", "")
    DB_NAME = os.getenv("DB_NAME", "postgres")

    DATABASE_URL = f"postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

    print("=== Миграция is_owner в users ===")
    print(f"База данных: {DB_NAME}")

    try:
        engine = create_engine(DATABASE_URL, echo=True)

        with engine.connect() as connection:
            check_column = text("""
                SELECT column_name
                FROM information_schema.columns
                WHERE table_name = 'users'
                AND column_name = 'is_owner';
            """)

            exists = connection.execute(check_column).fetchone()

            if not exists:
                print("Добавляем колонку is_owner...")
                connection.execute(text("""
                    ALTER TABLE users
                    ADD COLUMN is_owner BOOLEAN DEFAULT FALSE;
                """))

                print("Заполняем NULL значением FALSE...")
                connection.execute(text("""
                    UPDATE users
                    SET is_owner = FALSE
                    WHERE is_owner IS NULL;
                """))

                print("Делаем колонку обязательной (NOT NULL)...")
                connection.execute(text("""
                    ALTER TABLE users
                    ALTER COLUMN is_owner SET NOT NULL;
                """))
                print("✅ is_owner добавлен")
            else:
                print("✅ Колонка is_owner уже существует")

            # Если у пользователя уже есть квартиры, помечаем как владельца.
            print("Синхронизируем владельцев по properties.owner_id...")
            connection.execute(text("""
                UPDATE users u
                SET is_owner = TRUE
                WHERE EXISTS (
                    SELECT 1
                    FROM properties p
                    WHERE p.owner_id = u.id
                );
            """))

            connection.commit()
            print("\n🎉 Миграция успешно завершена")

    except Exception as e:
        print(f"❌ Ошибка миграции: {e}")
        return False

    return True


if __name__ == "__main__":
    migrate_user_is_owner()
