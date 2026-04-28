#!/usr/bin/env python3
"""
Миграция для добавления таблицы property_images
"""
import os
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

load_dotenv()


def migrate_property_images():
    DB_HOST = os.getenv("DB_HOST", "localhost")
    DB_PORT = os.getenv("DB_PORT", "5432")
    DB_USER = os.getenv("DB_USER", "postgres")
    DB_PASSWORD = os.getenv("DB_PASSWORD", "")
    DB_NAME = os.getenv("DB_NAME", "postgres")

    DATABASE_URL = f"postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

    print("=== Миграция property_images ===")
    print(f"База данных: {DB_NAME}")

    try:
        engine = create_engine(DATABASE_URL, echo=True)

        with engine.connect() as connection:
            check_table = text("""
                SELECT table_name
                FROM information_schema.tables
                WHERE table_name = 'property_images';
            """)

            exists = connection.execute(check_table).fetchone()

            if not exists:
                print("Создаем таблицу property_images...")
                connection.execute(text("""
                    CREATE TABLE property_images (
                        id SERIAL PRIMARY KEY,
                        property_id INTEGER NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
                        image_url VARCHAR(255) NOT NULL,
                        sort_order INTEGER DEFAULT 0,
                        created_at TIMESTAMP DEFAULT NOW()
                    );
                """))

                print("Добавляем индекс idx_property_images_property_id...")
                connection.execute(text("""
                    CREATE INDEX idx_property_images_property_id ON property_images(property_id);
                """))
                print("✅ Таблица property_images создана")
            else:
                print("✅ Таблица property_images уже существует")

            print("Синхронизируем старые данные properties.image_url -> property_images...")
            connection.execute(text("""
                INSERT INTO property_images (property_id, image_url, sort_order)
                SELECT p.id, p.image_url, 0
                FROM properties p
                WHERE p.image_url IS NOT NULL
                  AND NOT EXISTS (
                    SELECT 1
                    FROM property_images pi
                    WHERE pi.property_id = p.id
                      AND pi.image_url = p.image_url
                  );
            """))

            connection.commit()
            print("\n🎉 Миграция успешно завершена")

    except Exception as e:
        print(f"❌ Ошибка миграции: {e}")
        return False

    return True


if __name__ == "__main__":
    migrate_property_images()
