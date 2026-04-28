#!/bin/bash
echo "🚀 Запуск FastAPI сервера для мобильной разработки..."
echo "📡 Сервер будет доступен на:"
echo "   💻 Локально: http://localhost:8000"  
echo "   📱 WiFi:     http://192.168.10.16:8000"
echo "   📖 API Docs: http://192.168.10.16:8000/docs"
echo ""

# Останавливаем существующий сервер
pkill -f uvicorn 2>/dev/null

# Запускаем сервер на всех интерфейсах
/usr/local/bin/python3 -m uvicorn "import os:app" --reload --host 192.168.10.16 --port 8000