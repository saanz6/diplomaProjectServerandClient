import os
import uuid
import aiofiles
import io
from datetime import date, datetime, timedelta
from typing import List, Optional
from fastapi import FastAPI, HTTPException, Depends, status, Request, UploadFile, File, Form, Response
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, EmailStr
from sqlalchemy.orm import declarative_base, relationship, sessionmaker, Session, joinedload
from passlib.context import CryptContext
from dotenv import load_dotenv
from jose import JWTError, jwt
from google.auth.transport import requests
from google.oauth2 import id_token
import logging
from PIL import Image

# Настраиваем логирование
logging.basicConfig(level=logging.INFO)

# Загружаем переменные окружения из .env файла
load_dotenv()

# main.py
# Minimal FastAPI backend for the provided PostgreSQL schema.
# Requirements: fastapi, uvicorn, sqlalchemy, psycopg2-binary, pydantic, passlib[bcrypt]


from sqlalchemy import (
    create_engine, Column, Integer, String, Text, Boolean, DateTime, Date,
    ForeignKey, Table, Numeric, func, UniqueConstraint, Index, or_
)
from sqlalchemy.exc import IntegrityError

# Чтение параметров подключения к БД из переменных окружения
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")  # Задайте пароль через переменную окружения
DB_NAME = os.getenv("DB_NAME", "postgres")

DATABASE_URL = f"postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

engine = create_engine(DATABASE_URL, echo=False)
SessionLocal = sessionmaker(bind=engine)

Base = declarative_base()
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# JWT Configuration
SECRET_KEY = os.getenv("SECRET_KEY", "your-super-secret-key-change-in-production")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30

# Google OAuth Configuration
GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID", "")

# Конфигурация для загрузки файлов
UPLOAD_DIR = os.path.join(os.getcwd(), "uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(os.path.join(UPLOAD_DIR, "documents"), exist_ok=True)
os.makedirs(os.path.join(UPLOAD_DIR, "selfies"), exist_ok=True)
os.makedirs(os.path.join(UPLOAD_DIR, "properties"), exist_ok=True)

security = HTTPBearer()
optional_security = HTTPBearer(auto_error=False)

# Association table for property amenities
property_amenities = Table(
    "property_amenities",
    Base.metadata,
    Column("property_id", Integer, ForeignKey("properties.id", ondelete="CASCADE"), primary_key=True),
    Column("amenity_id", Integer, ForeignKey("amenities.id", ondelete="CASCADE"), primary_key=True),
)

# Favorites table (composite PK)
class Favorite(Base):
    __tablename__ = "favorites"
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    property_id = Column(Integer, ForeignKey("properties.id", ondelete="CASCADE"), primary_key=True)
    created_at = Column(DateTime, server_default=func.now())

# Tables reflecting the provided schema
class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True)
    name = Column(String(100), nullable=False)
    surname = Column(String(100), nullable=True)
    patronymic = Column(String(100), nullable=True)
    email = Column(String(150), unique=True, nullable=False)
    password_hash = Column(String(255), nullable=True)  # Nullable для OAuth пользователей
    avatar_url = Column(String(255))
    is_verified = Column(Boolean, default=False)
    is_owner = Column(Boolean, default=False)
    auth_provider = Column(String(20), default="email")  # "email" или "google"
    google_id = Column(String(100), unique=True, nullable=True)  # ID от Google
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    bookings = relationship("Booking", back_populates="user", cascade="all, delete-orphan")
    favorites = relationship("Property", secondary="favorites", back_populates="favorited_by")
    properties = relationship("Property", back_populates="owner")

class Property(Base):
    __tablename__ = "properties"
    id = Column(Integer, primary_key=True)
    title = Column(String(200), nullable=False)
    location = Column(String(100), nullable=False, index=True)
    address = Column(String(255), nullable=True)
    price_per_night = Column(Integer, nullable=False)
    rating = Column(Numeric(2,1), default=0)
    image_url = Column(String(255))
    rooms = Column(Integer, default=1)
    bathrooms = Column(Integer, default=1)
    description = Column(Text)
    owner_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    amenities = relationship("Amenity", secondary=property_amenities, back_populates="properties")
    bookings = relationship("Booking", back_populates="property", cascade="all, delete-orphan")
    favorited_by = relationship("User", secondary="favorites", back_populates="favorites")
    owner = relationship("User", back_populates="properties")
    images = relationship("PropertyImage", back_populates="property", cascade="all, delete-orphan")

    @property
    def image_urls(self):
        urls = []
        if self.image_url:
            urls.append(self.image_url)

        ordered_images = sorted(self.images or [], key=lambda img: ((img.sort_order or 0), (img.id or 0)))
        for image in ordered_images:
            if image.image_url and image.image_url not in urls:
                urls.append(image.image_url)
        return urls


class PropertyImage(Base):
    __tablename__ = "property_images"
    id = Column(Integer, primary_key=True)
    property_id = Column(Integer, ForeignKey("properties.id", ondelete="CASCADE"), nullable=False, index=True)
    image_url = Column(String(255), nullable=False)
    sort_order = Column(Integer, default=0)
    created_at = Column(DateTime, server_default=func.now())

    property = relationship("Property", back_populates="images")

class Amenity(Base):
    __tablename__ = "amenities"
    id = Column(Integer, primary_key=True)
    name = Column(String(100), nullable=False, unique=True)
    properties = relationship("Property", secondary=property_amenities, back_populates="amenities")

class Booking(Base):
    __tablename__ = "bookings"
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"))
    property_id = Column(Integer, ForeignKey("properties.id", ondelete="CASCADE"))
    check_in = Column(Date, nullable=False)
    check_out = Column(Date, nullable=False)
    guests = Column(Integer, default=1)
    total_price = Column(Integer, nullable=False)
    status = Column(String(20), default="pending")
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    user = relationship("User", back_populates="bookings")
    property = relationship("Property", back_populates="bookings")

class Verification(Base):
    __tablename__ = "verifications"
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"))
    document_type = Column(String(20), nullable=False)  # "passport", "idCard", "driver"
    document_url = Column(String(255), nullable=False)  # путь к файлу документа
    selfie_url = Column(String(255), nullable=False)   # путь к селфи
    status = Column(String(20), default="pending")     # "pending", "approved", "rejected"
    notes = Column(Text, nullable=True)                # заметки от модератора
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    user = relationship("User", backref="verifications")

class Review(Base):
    __tablename__ = "reviews"
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"))
    property_id = Column(Integer, ForeignKey("properties.id", ondelete="CASCADE"))
    rating = Column(Numeric(2,1), nullable=False)
    comment = Column(Text)
    created_at = Column(DateTime, server_default=func.now())

# Create indexes similar to the SQL schema (if not created by column args)
Index("idx_properties_location", Property.location)
Index("idx_bookings_user", Booking.user_id)
Index("idx_bookings_property", Booking.property_id)

Base.metadata.create_all(bind=engine)

# Pydantic schemas
class UserCreate(BaseModel):
    name: str
    surname: Optional[str] = None
    patronymic: Optional[str] = None
    email: EmailStr
    password: str
    is_owner: Optional[bool] = False
    # Backward compatibility for clients that send camelCase.
    isOwner: Optional[bool] = None

class UserOut(BaseModel):
    id: int
    name: str
    surname: Optional[str] = None
    patronymic: Optional[str] = None
    email: EmailStr
    avatar_url: Optional[str] = None
    is_verified: bool
    is_owner: bool = False
    auth_provider: str  # "email" или "google"
    created_at: datetime

    class Config:
        from_attributes = True

class UserLogin(BaseModel):
    email: EmailStr
    password: str

class GoogleTokenLogin(BaseModel):
    id_token: str

class Token(BaseModel):
    access_token: str
    token_type: str

class TokenWithUser(BaseModel):
    access_token: str
    token_type: str
    user: UserOut

class TokenData(BaseModel):
    email: Optional[str] = None

class AmenityCreate(BaseModel):
    name: str

class AmenityOut(BaseModel):
    id: int
    name: str

    class Config:
        from_attributes = True

class PropertyCreate(BaseModel):
    title: str
    location: str
    address: Optional[str] = None
    price_per_night: int
    image_url: Optional[str] = None
    image_urls: Optional[List[str]] = []
    rooms: Optional[int] = 1
    bathrooms: Optional[int] = 1
    description: Optional[str] = None
    amenity_ids: Optional[List[int]] = []
    amenities: Optional[List[str]] = []

class PropertyUpdate(BaseModel):
    title: Optional[str] = None
    location: Optional[str] = None
    address: Optional[str] = None
    price_per_night: Optional[int] = None
    image_url: Optional[str] = None
    image_urls: Optional[List[str]] = None
    rooms: Optional[int] = None
    bathrooms: Optional[int] = None
    description: Optional[str] = None
    amenity_ids: Optional[List[int]] = None
    amenities: Optional[List[str]] = None

class PropertyOut(BaseModel):
    id: int
    title: str
    location: str
    address: Optional[str] = None
    price_per_night: int
    rating: Optional[float] = None
    image_url: Optional[str] = None
    image_urls: List[str] = []
    rooms: int
    bathrooms: int
    description: Optional[str] = None
    owner_id: Optional[int] = None
    amenities: List[AmenityOut] = []

    class Config:
        from_attributes = True

class BookingCreate(BaseModel):
    property_id: int
    check_in: date
    check_out: date
    guests: Optional[int] = 1
    total_price: int

class PropertyInBooking(BaseModel):
    id: int
    title: str
    location: str
    address: Optional[str] = None

    class Config:
        from_attributes = True

class BookingUserOut(BaseModel):
    id: int
    name: str
    surname: Optional[str] = None
    patronymic: Optional[str] = None
    email: EmailStr

    class Config:
        from_attributes = True

class BookingOut(BaseModel):
    id: int
    user_id: int
    property_id: int
    check_in: date
    check_out: date
    guests: int
    total_price: int
    status: str
    created_at: datetime
    property: Optional[PropertyInBooking] = None
    user: Optional[BookingUserOut] = None

    class Config:
        from_attributes = True

class ContractOut(BaseModel):
    booking_id: int
    property_title: str
    check_in: date
    check_out: date
    created_at: datetime
    is_active: bool
    contract_url: str

class FavoriteCreate(BaseModel):
    property_id: int

class VerificationOut(BaseModel):
    id: int
    user_id: int
    document_type: str
    document_url: str
    selfie_url: str
    status: str
    notes: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True

class VerificationAdminOut(BaseModel):
    verification_id: Optional[int] = None
    user_id: int
    user_name: str
    user_surname: Optional[str] = None
    user_patronymic: Optional[str] = None
    user_email: str
    user_created_at: datetime
    is_verified: bool
    document_type: Optional[str] = None
    document_url: Optional[str] = None
    selfie_url: Optional[str] = None
    status: str  # pending | approved | rejected | not_submitted
    notes: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

class VerificationStatusUpdate(BaseModel):
    status: str  # "approved" или "rejected"
    notes: Optional[str] = None
    user_name: Optional[str] = None
    user_surname: Optional[str] = None
    user_patronymic: Optional[str] = None

class PropertyImageUploadOut(BaseModel):
    image_url: str

app = FastAPI(title="Property Rental API")

# Настройка CORS для доступа с мобильных устройств
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://127.0.0.1:3000", 
        "http://192.168.3.12:3000",  # Ваш WiFi IP
        "http://192.168.*.*:*",      # Любые локальные IP
        "*"  # В продакшене уберите это и оставьте только конкретные домены
    ],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)

# Настройка статических файлов для доступа к загруженным изображениям
app.mount("/uploads", StaticFiles(directory=UPLOAD_DIR), name="uploads")

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# Utilities
def hash_password(password: str) -> str:
    return pwd_context.hash(password)

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=15)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

def authenticate_user(db: Session, email: str, password: str):
    user = db.query(User).filter(User.email == email).first()
    if not user:
        return False
    if not verify_password(password, user.password_hash):
        return False
    return user

def get_or_create_amenities(
    db: Session,
    amenity_ids: Optional[List[int]] = None,
    amenity_names: Optional[List[str]] = None,
) -> List[Amenity]:
    collected: List[Amenity] = []
    seen_ids = set()

    if amenity_ids:
        by_ids = db.query(Amenity).filter(Amenity.id.in_(amenity_ids)).all()
        for amenity in by_ids:
            if amenity.id not in seen_ids:
                collected.append(amenity)
                seen_ids.add(amenity.id)

    if amenity_names:
        for raw_name in amenity_names:
            name = (raw_name or "").strip()
            if not name:
                continue

            amenity = db.query(Amenity).filter(func.lower(Amenity.name) == name.lower()).first()
            if not amenity:
                amenity = Amenity(name=name)
                db.add(amenity)
                db.flush()

            if amenity.id not in seen_ids:
                collected.append(amenity)
                seen_ids.add(amenity.id)

    return collected

async def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security), db: Session = Depends(get_db)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(credentials.credentials, SECRET_KEY, algorithms=[ALGORITHM])
        email: str = payload.get("sub")
        if email is None:
            raise credentials_exception
        token_data = TokenData(email=email)
    except JWTError:
        raise credentials_exception
    user = db.query(User).filter(User.email == token_data.email).first()
    if user is None:
        raise credentials_exception
    return user

def verify_google_token(token: str):
    """Верифицирует Google ID токен и возвращает информацию о пользователе"""
    try:
        # Verification Google ID token
        idinfo = id_token.verify_oauth2_token(token, requests.Request(), GOOGLE_CLIENT_ID)
        
        # Проверяем, что токен от Google
        if idinfo['iss'] not in ['accounts.google.com', 'https://accounts.google.com']:
            raise ValueError('Wrong issuer.')
            
        return {
            'google_id': idinfo['sub'],
            'email': idinfo['email'],
            'name': idinfo.get('name', ''),
            'picture': idinfo.get('picture', ''),
            'verified_email': idinfo.get('email_verified', False)
        }
    except ValueError:
        return None

def get_or_create_google_user(db: Session, google_user_info: dict):
    """Находит существующего пользователя или создает нового через Google OAuth"""
    # Сначала ищем по Google ID
    user = db.query(User).filter(User.google_id == google_user_info['google_id']).first()
    
    if user:
        return user
    
    # Затем ищем по email (возможно, пользователь уже регистрировался через email)
    user = db.query(User).filter(User.email == google_user_info['email']).first()
    
    if user:
        # Обновляем существующего пользователя информацией от Google
        user.google_id = google_user_info['google_id']
        user.auth_provider = "google"
        user.avatar_url = google_user_info.get('picture')
        user.is_verified = google_user_info.get('verified_email', False)
        db.commit()
        return user
    
    # Создаем нового пользователя
    user = User(
        name=google_user_info['name'],
        email=google_user_info['email'],
        google_id=google_user_info['google_id'],
        auth_provider="google",
        avatar_url=google_user_info.get('picture'),
        is_verified=google_user_info.get('verified_email', False),
        is_owner=False,
        password_hash=None  # У OAuth пользователей нет пароля
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user

async def save_upload_file(upload_file: UploadFile, folder: str) -> str:
    """Сохраняет загруженный файл и возвращает путь к нему"""
    # Генерируем уникальное имя файла
    file_extension = upload_file.filename.split(".")[-1] if upload_file.filename else "jpg"
    unique_filename = f"{uuid.uuid4()}.{file_extension}"
    
    # Полный путь к файлу
    file_path = os.path.join(UPLOAD_DIR, folder, unique_filename)
    
    # Сохраняем файл
    async with aiofiles.open(file_path, 'wb') as out_file:
        content = await upload_file.read()
        await out_file.write(content)
    
    # Возвращаем относительный путь для сохранения в БД
    return f"uploads/{folder}/{unique_filename}"

def validate_image_file(upload_file: UploadFile) -> bool:
    """Проверяет, является ли файл изображением"""
    if not upload_file.content_type or not upload_file.content_type.startswith("image/"):
        return False
    
    allowed_extensions = {"jpg", "jpeg", "png", "webp"}
    if upload_file.filename:
        extension = upload_file.filename.split(".")[-1].lower()
        return extension in allowed_extensions
    
    return False

def resize_image_if_needed(file_path: str, max_size: tuple = (1920, 1080)) -> None:
    """Изменяет размер изображения если оно слишком большое"""
    try:
        with Image.open(file_path) as img:
            if img.size[0] > max_size[0] or img.size[1] > max_size[1]:
                img.thumbnail(max_size, Image.Resampling.LANCZOS)
                img.save(file_path, optimize=True, quality=85)
    except Exception as e:
        logging.error(f"Ошибка при изменении размера изображения {file_path}: {e}")


def normalize_image_urls(primary_url: Optional[str], urls: Optional[List[str]]) -> List[str]:
    collected: List[str] = []

    if primary_url and primary_url.strip():
        collected.append(primary_url.strip())

    if urls:
        for raw_url in urls:
            clean_url = (raw_url or "").strip()
            if clean_url and clean_url not in collected:
                collected.append(clean_url)

    return collected

def format_full_name(user: User) -> str:
    parts = [user.surname or "", user.name or "", user.patronymic or ""]
    full_name = " ".join(part.strip() for part in parts if (part or "").strip())
    return full_name or user.email


def build_contract_lines(
    booking: Booking,
    property_title: str,
    property_address: str,
    owner_name: str,
    owner_email: str,
    tenant_name: str,
    tenant_email: str,
) -> List[str]:
    contract_date = booking.created_at.strftime('%d.%m.%Y')
    check_in_str = booking.check_in.strftime('%d.%m.%Y')
    check_out_str = booking.check_out.strftime('%d.%m.%Y')
    nights = max((booking.check_out - booking.check_in).days, 1)
    nightly_price = int(round(booking.total_price / nights)) if nights else booking.total_price

    return [
        f"ДОГОВОР КРАТКОСРОЧНОЙ АРЕНДЫ ЖИЛОГО ПОМЕЩЕНИЯ №{booking.id}",
        f"Дата формирования: {contract_date}",
        "",
        f"Арендодатель: {owner_name}, контакт: {owner_email}",
        f"Арендатор: {tenant_name}, контакт: {tenant_email}",
        f"Объект аренды: {property_title}, адрес: {property_address}",
        f"Период аренды: {check_in_str} - {check_out_str} ({nights} ноч.)",
        f"Количество гостей: {booking.guests}",
        f"Стоимость: {booking.total_price} тг (ориентировочно {nightly_price} тг/ночь)",
        f"Статус бронирования: {booking.status}",
        "",
        "1. Предмет договора",
        "1.1. Арендодатель предоставляет Арендатору жилое помещение во временное возмездное пользование.",
        "1.2. Арендатор использует помещение только в жилых целях и соблюдает правила проживания.",
        "",
        "2. Права и обязанности Арендодателя",
        "2.1. Передать помещение в пригодном для проживания состоянии в согласованную дату заезда.",
        "2.2. Обеспечить доступ к помещению и коммунальным услугам в пределах технической возможности.",
        "2.3. Не препятствовать законному пользованию помещением в период аренды.",
        "2.4. Требовать соблюдения правил проживания и возмещения документально подтвержденного ущерба.",
        "",
        "3. Права и обязанности Арендатора",
        "3.1. Своевременно оплатить аренду по условиям бронирования.",
        "3.2. Бережно использовать помещение и соблюдать санитарные и противопожарные требования.",
        "3.3. Не передавать помещение третьим лицам и не превышать согласованное число гостей.",
        "3.4. Возместить ущерб имуществу, причиненный Арендатором или его гостями.",
        "3.5. Освободить помещение в дату выезда и передать его с учетом нормального износа.",
        "",
        "4. Стоимость, расчеты и отмена",
        f"4.1. Общая стоимость аренды составляет {booking.total_price} тг.",
        "4.2. Порядок оплаты, возвратов и удержаний определяется правилами сервиса и законом.",
        "4.3. При отмене бронирования применяются условия отмены, действующие в сервисе.",
        "",
        "5. Ответственность сторон",
        "5.1. Стороны несут ответственность за неисполнение обязательств в соответствии с законом.",
        "5.2. Арендодатель отвечает за достоверность сведений о помещении и правомерность аренды.",
        "5.3. Арендатор отвечает за соблюдение правил проживания и действия приглашенных им лиц.",
        "5.4. Нарушившая сторона возмещает другой стороне документально подтвержденные убытки.",
        "",
        "6. Форс-мажор",
        "6.1. Стороны освобождаются от ответственности при обстоятельствах непреодолимой силы.",
        "6.2. Сторона обязана уведомить другую сторону в разумный срок.",
        "",
        "7. Срок действия и расторжение",
        "7.1. Договор действует с момента подтверждения бронирования до полного исполнения обязательств.",
        "7.2. Расторжение возможно по соглашению сторон либо на основаниях закона и правил сервиса.",
        "",
        "8. Порядок разрешения споров",
        "8.1. Споры решаются путем переговоров и письменных претензий.",
        "8.2. При недостижении соглашения спор разрешается в порядке, установленном законом.",
        "",
        "9. Заключительные положения",
        "9.1. Договор сформирован автоматически в электронной форме на основании данных бронирования.",
        "9.2. Для усиленной доказательственной силы стороны вправе подписать договор на бумаге или КЭП.",
        "9.3. Неурегулированные вопросы решаются по действующему законодательству.",
        "",
        f"Арендодатель: {owner_name}",
        f"Арендатор: {tenant_name}",
    ]


def _pick_pdf_font_path() -> Optional[str]:
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
        "/Library/Fonts/Arial Unicode.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    return None

# Endpoints
@app.post("/users", response_model=UserOut)
def create_user(u: UserCreate, db: Session = Depends(get_db)):
    existing = db.query(User).filter(User.email == u.email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")
    owner_flag = u.is_owner
    if u.isOwner is not None:
        owner_flag = u.isOwner

    user = User(
        name=u.name, 
        surname=u.surname,
        patronymic=u.patronymic,
        email=u.email, 
        password_hash=hash_password(u.password),
        is_owner=bool(owner_flag),
        auth_provider="email"  # Указываем способ регистрации
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user

@app.get("/users/{user_id}", response_model=UserOut)
def get_user(user_id: int, db: Session = Depends(get_db)):
    user = db.query(User).get(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user

@app.post("/login", response_model=TokenWithUser)
def login_for_access_token(user_login: UserLogin, db: Session = Depends(get_db)):
    user = authenticate_user(db, user_login.email, user_login.password)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user.email}, expires_delta=access_token_expires
    )
    return {
        "access_token": access_token, 
        "token_type": "bearer",
        "user": user
    }

@app.post("/auth/google", response_model=TokenWithUser)
def google_auth(google_token: GoogleTokenLogin, db: Session = Depends(get_db)):
    """Аутентификация через Google OAuth"""
    logging.info(f"Google OAuth запрос получен. Token length: {len(google_token.id_token) if google_token.id_token else 'None'}")
    
    # Верифицируем Google ID токен
    google_user_info = verify_google_token(google_token.id_token)
    
    if not google_user_info:
        logging.error("Неверный Google токен")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Google token"
        )
    
    logging.info(f"Google пользователь: {google_user_info.get('name', 'Unknown')} ({google_user_info.get('email', 'No email')})")
    
    # Находим или создаем пользователя
    user = get_or_create_google_user(db, google_user_info)
    
    # Создаем JWT токен
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user.email}, expires_delta=access_token_expires
    )
    
    return {
        "access_token": access_token,
        "token_type": "bearer", 
        "user": user
    }

@app.post("/debug/google")
async def debug_google_request(request: Request):
    """Отладочный эндпоинт для проверки входящих данных от клиента"""
    body = await request.body()
    headers = dict(request.headers)
    
    try:
        import json
        json_data = json.loads(body.decode())
        logging.info(f"Получены JSON данные: {json_data}")
        return {
            "received_data": json_data,
            "headers": headers,
            "content_type": headers.get("content-type", ""),
            "data_keys": list(json_data.keys()) if isinstance(json_data, dict) else "not dict"
        }
    except Exception as e:
        logging.error(f"Ошибка парсинга JSON: {e}")
        return {
            "error": str(e),
            "raw_body": body.decode() if body else "empty",
            "headers": headers
        }

@app.get("/me", response_model=UserOut)
async def read_users_me(current_user: User = Depends(get_current_user)):
    return current_user

@app.post("/me/become-owner", response_model=UserOut)
def become_owner(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Переключает текущего пользователя в роль владельца жилья."""
    if not current_user.is_owner:
        current_user.is_owner = True
        db.commit()
        db.refresh(current_user)
    return current_user

@app.post("/amenities", response_model=AmenityOut)
def create_amenity(a: AmenityCreate, db: Session = Depends(get_db)):
    existing = db.query(Amenity).filter(Amenity.name == a.name).first()
    if existing:
        raise HTTPException(status_code=400, detail="Amenity already exists")
    am = Amenity(name=a.name)
    db.add(am)
    db.commit()
    db.refresh(am)
    return am

@app.get("/amenities", response_model=List[AmenityOut])
def list_amenities(db: Session = Depends(get_db)):
    return db.query(Amenity).all()

@app.get("/amenities/{amenity_id}", response_model=AmenityOut)
def get_amenity(amenity_id: int, db: Session = Depends(get_db)):
    amenity = db.query(Amenity).get(amenity_id)
    if not amenity:
        raise HTTPException(status_code=404, detail="Amenity not found")
    return amenity

@app.post("/properties", response_model=PropertyOut)
def create_property(
    p: PropertyCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not current_user.is_verified:
        raise HTTPException(status_code=403, detail="Только верифицированный владелец может добавлять квартиры")

    image_urls = normalize_image_urls(p.image_url, p.image_urls)

    prop = Property(
        title=p.title,
        location=p.location,
        address=p.address,
        price_per_night=p.price_per_night,
        image_url=image_urls[0] if image_urls else None,
        rooms=p.rooms,
        bathrooms=p.bathrooms,
        description=p.description,
        owner_id=current_user.id,
    )
    amenities = get_or_create_amenities(db, p.amenity_ids, p.amenities)
    if amenities:
        prop.amenities = amenities
    db.add(prop)
    db.flush()

    if image_urls:
        for index, image_url in enumerate(image_urls):
            db.add(PropertyImage(property_id=prop.id, image_url=image_url, sort_order=index))

    # После первой публикации пользователь считается владельцем.
    if not current_user.is_owner:
        current_user.is_owner = True

    db.commit()
    db.refresh(prop)
    return prop

@app.post("/properties/upload-image", response_model=PropertyImageUploadOut)
async def upload_property_image(
    image_file: UploadFile = File(..., description="Изображение квартиры"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not current_user.is_owner:
        raise HTTPException(status_code=403, detail="Только владелец может загружать фото квартиры")
    if not current_user.is_verified:
        raise HTTPException(status_code=403, detail="Только верифицированный владелец может загружать фото квартиры")

    if not validate_image_file(image_file):
        raise HTTPException(status_code=400, detail="Фото квартиры должно быть изображением (jpg, png, webp)")

    try:
        image_path = await save_upload_file(image_file, "properties")
        full_path = os.path.join(os.getcwd(), image_path)
        resize_image_if_needed(full_path)
        return {"image_url": image_path}
    except Exception as e:
        logging.error(f"Ошибка при загрузке фото квартиры: {e}")
        raise HTTPException(status_code=500, detail="Ошибка при сохранении фото квартиры")

@app.get("/properties", response_model=List[PropertyOut])
def list_properties(location: Optional[str] = None, db: Session = Depends(get_db)):
    q = db.query(Property).options(joinedload(Property.amenities), joinedload(Property.images))
    if location:
        q = q.filter(Property.location.ilike(f"%{location}%"))
    return q.all()

@app.get("/my/properties", response_model=List[PropertyOut])
def list_my_properties(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return (
        db.query(Property)
        .options(joinedload(Property.amenities), joinedload(Property.images))
        .filter(Property.owner_id == current_user.id)
        .order_by(Property.created_at.desc())
        .all()
    )

@app.get("/properties/{prop_id}", response_model=PropertyOut)
def get_property(prop_id: int, db: Session = Depends(get_db)):
    prop = db.query(Property).options(joinedload(Property.amenities), joinedload(Property.images)).get(prop_id)
    if not prop:
        raise HTTPException(status_code=404, detail="Property not found")
    return prop

@app.put("/properties/{prop_id}", response_model=PropertyOut)
def update_property(
    prop_id: int,
    p: PropertyUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    prop = db.query(Property).options(joinedload(Property.amenities), joinedload(Property.images)).filter(Property.id == prop_id).first()
    if not prop:
        raise HTTPException(status_code=404, detail="Property not found")
    if prop.owner_id != current_user.id:
        raise HTTPException(status_code=403, detail="You can edit only your own properties")

    # Название, город и адрес менять нельзя после создания.
    if p.title is not None or p.location is not None or p.address is not None:
        raise HTTPException(
            status_code=403,
            detail="Нельзя изменять название, город и адрес квартиры",
        )

    if p.price_per_night is not None:
        prop.price_per_night = p.price_per_night
    if p.image_urls is not None:
        normalized_urls = normalize_image_urls(p.image_url, p.image_urls)
        prop.image_url = normalized_urls[0] if normalized_urls else None
        prop.images = [
            PropertyImage(image_url=image_url, sort_order=index)
            for index, image_url in enumerate(normalized_urls)
        ]
    elif p.image_url is not None:
        prop.image_url = p.image_url
        if p.image_url.strip():
            existing_urls = [img.image_url for img in prop.images]
            if p.image_url not in existing_urls:
                prop.images.insert(0, PropertyImage(image_url=p.image_url, sort_order=0))
                for index, image in enumerate(prop.images):
                    image.sort_order = index
    if p.rooms is not None:
        prop.rooms = p.rooms
    if p.bathrooms is not None:
        prop.bathrooms = p.bathrooms
    if p.description is not None:
        prop.description = p.description

    if p.amenity_ids is not None or p.amenities is not None:
        prop.amenities = get_or_create_amenities(db, p.amenity_ids, p.amenities)

    db.commit()
    db.refresh(prop)
    return prop

@app.delete("/properties/{prop_id}", status_code=200)
def delete_property(
    prop_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    prop = db.query(Property).filter(Property.id == prop_id).first()
    if not prop:
        raise HTTPException(status_code=404, detail="Property not found")
    if prop.owner_id != current_user.id:
        raise HTTPException(status_code=403, detail="You can delete only your own properties")

    db.delete(prop)
    db.commit()
    return {"detail": "Property deleted"}

@app.post("/properties/{prop_id}/amenities", response_model=PropertyOut)
def add_amenity_to_property(prop_id: int, amenity: AmenityCreate, db: Session = Depends(get_db)):
    prop = db.query(Property).get(prop_id)
    if not prop:
        raise HTTPException(status_code=404, detail="Property not found")
    am = db.query(Amenity).filter(Amenity.name == amenity.name).first()
    if not am:
        am = Amenity(name=amenity.name)
        db.add(am)
        db.flush()
    if am not in prop.amenities:
        prop.amenities.append(am)
    db.commit()
    db.refresh(prop)
    return prop

@app.post("/bookings", response_model=BookingOut)
def create_booking(b: BookingCreate, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    # basic overlap check
    overlap = db.query(Booking).filter(
        Booking.property_id == b.property_id,
        Booking.status != "cancelled",
        Booking.check_in < b.check_out,
        Booking.check_out > b.check_in
    ).first()
    if overlap:
        raise HTTPException(status_code=400, detail="Property is already booked for requested dates")
    booking = Booking(
        user_id=current_user.id,
        property_id=b.property_id,
        check_in=b.check_in,
        check_out=b.check_out,
        guests=b.guests,
        total_price=b.total_price
    )
    db.add(booking)
    db.commit()
    return db.query(Booking).options(joinedload(Booking.property), joinedload(Booking.user)).get(booking.id)

@app.get("/bookings", response_model=List[BookingOut])
def list_bookings(user_id: Optional[int] = None, db: Session = Depends(get_db)):
    q = db.query(Booking).options(joinedload(Booking.property), joinedload(Booking.user))
    if user_id:
        q = q.filter(Booking.user_id == user_id)
    return q.all()

@app.get("/my/bookings", response_model=List[BookingOut])
def list_my_bookings(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Возвращает только бронирования текущего авторизованного пользователя"""
    return (
        db.query(Booking)
        .options(joinedload(Booking.property), joinedload(Booking.user))
        .filter(Booking.user_id == current_user.id)
        .all()
    )

@app.get("/my/contracts", response_model=List[ContractOut])
def list_my_contracts(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    bookings = (
        db.query(Booking)
        .options(joinedload(Booking.property))
        .join(Property, Booking.property_id == Property.id)
        .filter(
            or_(
                Booking.user_id == current_user.id,
                Property.owner_id == current_user.id,
            )
        )
        .order_by(Booking.created_at.desc())
        .all()
    )

    base_url = str(request.base_url).rstrip("/")
    today = date.today()
    return [
        ContractOut(
            booking_id=booking.id,
            property_title=booking.property.title if booking.property else f"Квартира #{booking.property_id}",
            check_in=booking.check_in,
            check_out=booking.check_out,
            created_at=booking.created_at,
            is_active=(booking.status != "cancelled" and booking.check_out >= today),
            contract_url=f"{base_url}/bookings/{booking.id}/contract.pdf",
        )
        for booking in bookings
    ]


@app.get("/bookings/{booking_id}/contract", response_class=HTMLResponse)
def get_booking_contract(
    booking_id: int,
    token: Optional[str] = None,
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(optional_security),
    db: Session = Depends(get_db),
):
    raw_token = token or (credentials.credentials if credentials else None)
    if not raw_token:
        raise HTTPException(status_code=401, detail="Could not validate credentials")

    try:
        payload = jwt.decode(raw_token, SECRET_KEY, algorithms=[ALGORITHM])
        email: str = payload.get("sub")
        if email is None:
            raise HTTPException(status_code=401, detail="Could not validate credentials")
    except JWTError:
        raise HTTPException(status_code=401, detail="Could not validate credentials")

    current_user = db.query(User).filter(User.email == email).first()
    if not current_user:
        raise HTTPException(status_code=401, detail="Could not validate credentials")

    booking = (
        db.query(Booking)
        .options(joinedload(Booking.property).joinedload(Property.owner), joinedload(Booking.user))
        .filter(Booking.id == booking_id)
        .first()
    )
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found")

    is_tenant = booking.user_id == current_user.id
    is_owner = bool(booking.property and booking.property.owner_id == current_user.id)
    if not is_tenant and not is_owner:
        raise HTTPException(status_code=403, detail="You can view only your own contract")

    property_title = booking.property.title if booking.property else f"Квартира #{booking.property_id}"
    property_address = booking.property.address if booking.property else "Не указан"
    owner = booking.property.owner if booking.property else None
    owner_name = format_full_name(owner) if owner else "Не указан"
    tenant_name = format_full_name(booking.user)
    owner_email = owner.email if owner else "Не указан"
    tenant_email = booking.user.email if booking.user else "Не указан"
    contract_date = booking.created_at.strftime('%d.%m.%Y')
    check_in_str = booking.check_in.strftime('%d.%m.%Y')
    check_out_str = booking.check_out.strftime('%d.%m.%Y')
    nights = max((booking.check_out - booking.check_in).days, 1)
    nightly_price = int(round(booking.total_price / nights)) if nights else booking.total_price

    contract_html = f"""
<!doctype html>
<html lang=\"ru\">
<head>
  <meta charset=\"utf-8\" />
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
  <title>Договор аренды #{booking.id}</title>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; margin: 28px; color: #1b1b1b; }}
        h1 {{ margin-bottom: 6px; }}
        h2 {{ margin-top: 20px; margin-bottom: 8px; font-size: 18px; }}
        p, li {{ line-height: 1.45; }}
        ol {{ margin-top: 4px; padding-left: 20px; }}
    .muted {{ color: #5b6472; }}
    .block {{ margin-top: 20px; padding: 14px; border: 1px solid #e3e7ee; border-radius: 10px; }}
        .signatures {{ margin-top: 28px; display: grid; grid-template-columns: 1fr 1fr; gap: 24px; }}
        .line {{ margin-top: 36px; border-top: 1px solid #222; padding-top: 6px; font-size: 13px; }}
  </style>
</head>
<body>
    <h1>ДОГОВОР КРАТКОСРОЧНОЙ АРЕНДЫ ЖИЛОГО ПОМЕЩЕНИЯ</h1>
  <div class=\"muted\">Номер договора: {booking.id}</div>
    <div class=\"muted\">Дата формирования: {contract_date}</div>

  <div class=\"block\">
        <p><strong>Арендодатель:</strong> {owner_name}, контакт: {owner_email}</p>
        <p><strong>Арендатор:</strong> {tenant_name}, контакт: {tenant_email}</p>
        <p><strong>Объект аренды:</strong> {property_title}, адрес: {property_address}</p>
        <p><strong>Период аренды:</strong> {check_in_str} - {check_out_str} ({nights} ноч.)</p>
    <p><strong>Количество гостей:</strong> {booking.guests}</p>
        <p><strong>Стоимость:</strong> {booking.total_price} тг (ориентировочно {nightly_price} тг/ночь)</p>
    <p><strong>Статус бронирования:</strong> {booking.status}</p>
  </div>

  <div class=\"block\">
        <h2>1. Предмет договора</h2>
        <ol>
            <li>Арендодатель предоставляет Арендатору во временное возмездное пользование жилое помещение, указанное выше, на срок, определенный условиями бронирования.</li>
            <li>Арендатор принимает помещение для проживания и обязуется использовать его исключительно в жилых целях, с соблюдением правил проживания и общественного порядка.</li>
        </ol>

        <h2>2. Права и обязанности Арендодателя</h2>
        <ol>
            <li>Передать помещение в состоянии, пригодном для проживания, в согласованную дату заезда.</li>
            <li>Обеспечить доступ Арендатора к помещению и основным коммунальным услугам в пределах технической возможности.</li>
            <li>Не препятствовать законному пользованию помещением Арендатором в период аренды.</li>
            <li>Иметь право требовать соблюдения правил проживания, сохранности имущества и возмещения документально подтвержденного ущерба.</li>
        </ol>

        <h2>3. Права и обязанности Арендатора</h2>
        <ol>
            <li>Своевременно оплатить стоимость аренды в размере и сроках, предусмотренных бронированием.</li>
            <li>Использовать помещение бережно, соблюдать санитарные, противопожарные и иные обязательные требования.</li>
            <li>Не передавать помещение третьим лицам и не заселять лиц сверх согласованного количества гостей без согласия Арендодателя.</li>
            <li>Возместить причиненный по вине Арендатора или его гостей ущерб имуществу Арендодателя.</li>
            <li>Освободить помещение в дату выезда и передать его в состоянии, соответствующем нормальному износу.</li>
        </ol>

        <h2>4. Стоимость, порядок расчетов и отмена</h2>
        <ol>
            <li>Общая стоимость аренды составляет {booking.total_price} тг и формируется сервисом на основании условий бронирования.</li>
            <li>Порядок оплаты, возвратов и удержаний определяется правилами сервиса и применимыми нормами законодательства.</li>
            <li>В случае отмены бронирования применяются условия отмены, действующие на момент оформления брони.</li>
        </ol>

        <h2>5. Ответственность сторон</h2>
        <ol>
            <li>За неисполнение или ненадлежащее исполнение обязательств по настоящему договору стороны несут ответственность в соответствии с законодательством и условиями сервиса.</li>
            <li>Арендодатель отвечает за достоверность сведений о помещении и правомерность его предоставления в аренду.</li>
            <li>Арендатор отвечает за соблюдение правил проживания, сохранность имущества и действия приглашенных им лиц.</li>
            <li>Сторона, нарушившая обязательства, обязана возместить другой стороне фактически причиненные и документально подтвержденные убытки.</li>
        </ol>

        <h2>6. Форс-мажор</h2>
        <ol>
            <li>Стороны освобождаются от ответственности за полное или частичное неисполнение обязательств при наступлении обстоятельств непреодолимой силы, подтвержденных надлежащими доказательствами.</li>
            <li>Сторона, для которой создалась невозможность исполнения, обязана уведомить другую сторону в разумный срок.</li>
        </ol>

        <h2>7. Срок действия и расторжение</h2>
        <ol>
            <li>Договор вступает в силу с момента подтверждения бронирования и действует до полного исполнения обязательств сторонами.</li>
            <li>Договор может быть расторгнут по соглашению сторон либо по иным основаниям, предусмотренным законодательством и правилами сервиса.</li>
        </ol>

        <h2>8. Порядок разрешения споров</h2>
        <ol>
            <li>Споры и разногласия стороны стремятся урегулировать путем переговоров и обмена письменными претензиями.</li>
            <li>При недостижении соглашения спор подлежит разрешению в порядке, установленном действующим законодательством по месту подсудности, определяемому такими нормами.</li>
        </ol>

        <h2>9. Заключительные положения</h2>
        <ol>
            <li>Договор сформирован автоматически в электронной форме на основании данных бронирования в приложении.</li>
            <li>Для придания документу усиленной доказательственной силы стороны вправе подписать его на бумажном носителе либо квалифицированной электронной подписью.</li>
            <li>Во всем, что не урегулировано настоящим договором, стороны руководствуются действующим законодательством и правилами сервиса.</li>
        </ol>
  </div>

    <div class=\"signatures\">
        <div>
            <strong>Арендодатель</strong>
            <div class=\"line\">{owner_name}</div>
        </div>
        <div>
            <strong>Арендатор</strong>
            <div class=\"line\">{tenant_name}</div>
        </div>
    </div>
</body>
</html>
"""

    return HTMLResponse(content=contract_html)


@app.get("/bookings/{booking_id}/contract.pdf")
def get_booking_contract_pdf(
    booking_id: int,
    token: Optional[str] = None,
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(optional_security),
    db: Session = Depends(get_db),
):
    raw_token = token or (credentials.credentials if credentials else None)
    if not raw_token:
        raise HTTPException(status_code=401, detail="Could not validate credentials")

    try:
        payload = jwt.decode(raw_token, SECRET_KEY, algorithms=[ALGORITHM])
        email: str = payload.get("sub")
        if email is None:
            raise HTTPException(status_code=401, detail="Could not validate credentials")
    except JWTError:
        raise HTTPException(status_code=401, detail="Could not validate credentials")

    current_user = db.query(User).filter(User.email == email).first()
    if not current_user:
        raise HTTPException(status_code=401, detail="Could not validate credentials")

    booking = (
        db.query(Booking)
        .options(joinedload(Booking.property).joinedload(Property.owner), joinedload(Booking.user))
        .filter(Booking.id == booking_id)
        .first()
    )
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found")

    is_tenant = booking.user_id == current_user.id
    is_owner = bool(booking.property and booking.property.owner_id == current_user.id)
    if not is_tenant and not is_owner:
        raise HTTPException(status_code=403, detail="You can view only your own contract")

    property_title = booking.property.title if booking.property else f"Квартира #{booking.property_id}"
    property_address = booking.property.address if booking.property else "Не указан"
    owner = booking.property.owner if booking.property else None
    owner_name = format_full_name(owner) if owner else "Не указан"
    tenant_name = format_full_name(booking.user)
    owner_email = owner.email if owner else "Не указан"
    tenant_email = booking.user.email if booking.user else "Не указан"

    lines = build_contract_lines(
        booking=booking,
        property_title=property_title,
        property_address=property_address,
        owner_name=owner_name,
        owner_email=owner_email,
        tenant_name=tenant_name,
        tenant_email=tenant_email,
    )

    try:
        from reportlab.lib.pagesizes import A4
        from reportlab.pdfbase import pdfmetrics
        from reportlab.pdfbase.ttfonts import TTFont
        from reportlab.pdfgen import canvas
    except Exception:
                escaped_lines = [
                        line.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                        for line in lines
                ]
                html_fallback = "<br/>".join(escaped_lines)
                return HTMLResponse(
                        content=f"""
<!doctype html>
<html lang=\"ru\">
<head>
    <meta charset=\"utf-8\" />
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
    <title>Договор аренды #{booking.id}</title>
    <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; margin: 24px; color: #1b1b1b; }}
        .note {{ margin-bottom: 16px; padding: 10px 12px; border: 1px solid #f0c36d; border-radius: 8px; background: #fff7e6; }}
        .doc {{ line-height: 1.5; white-space: normal; }}
    </style>
</head>
<body>
    <div class=\"note\">PDF временно недоступен на сервере (не установлен reportlab). Показана HTML-версия договора.</div>
    <div class=\"doc\">{html_fallback}</div>
</body>
</html>
"""
                )

    buffer = io.BytesIO()
    pdf = canvas.Canvas(buffer, pagesize=A4)
    width, height = A4

    font_path = _pick_pdf_font_path()
    font_name = "Helvetica"
    if font_path:
        try:
            pdfmetrics.registerFont(TTFont("ContractFont", font_path))
            font_name = "ContractFont"
        except Exception:
            font_name = "Helvetica"

    y = height - 40
    pdf.setFont(font_name, 11)
    for line in lines:
        if y < 40:
            pdf.showPage()
            pdf.setFont(font_name, 11)
            y = height - 40
        pdf.drawString(36, y, line)
        y -= 16

    pdf.save()
    pdf_bytes = buffer.getvalue()
    buffer.close()

    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f"inline; filename=contract_{booking.id}.pdf",
            "Cache-Control": "no-store",
        },
    )


@app.patch("/bookings/{booking_id}/cancel", response_model=BookingOut)
def cancel_my_booking(
    booking_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    booking = (
        db.query(Booking)
        .options(joinedload(Booking.property), joinedload(Booking.user))
        .filter(Booking.id == booking_id)
        .first()
    )
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found")
    if booking.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="You can cancel only your own bookings")

    if booking.status != "cancelled":
        booking.status = "cancelled"
        db.commit()
        db.refresh(booking)

    return booking

@app.post("/favorites", status_code=201)
def add_favorite(f: FavoriteCreate, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    property_exists = db.query(Property.id).filter(Property.id == f.property_id).first()
    if not property_exists:
        raise HTTPException(status_code=404, detail="Property not found")

    exists = db.query(Favorite).filter(Favorite.user_id == current_user.id, Favorite.property_id == f.property_id).first()
    if exists:
        raise HTTPException(status_code=400, detail="Already favorited")

    fav = Favorite(user_id=current_user.id, property_id=f.property_id)
    db.add(fav)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=400, detail="Could not add favorite")
    return {"detail": "Favorited"}

@app.delete("/favorites/{property_id}", status_code=200)
def remove_favorite(property_id: int, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    favorite = db.query(Favorite).filter(
        Favorite.user_id == current_user.id,
        Favorite.property_id == property_id,
    ).first()

    if not favorite:
        raise HTTPException(status_code=404, detail="Favorite not found")

    db.delete(favorite)
    db.commit()
    return {"detail": "Removed from favorites"}

@app.get("/favorites", response_model=List[PropertyOut])
def get_my_favorites(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Возвращает избранные квартиры текущего авторизованного пользователя"""
    user = db.query(User).options(joinedload(User.favorites).joinedload(Property.amenities)).get(current_user.id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user.favorites

@app.get("/favorites/{user_id}", response_model=List[PropertyOut])
def get_favorites(user_id: int, db: Session = Depends(get_db)):
    user = db.query(User).get(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user.favorites

# Simple review creation
class ReviewCreate(BaseModel):
    user_id: int
    property_id: int
    rating: float
    comment: Optional[str] = None

@app.post("/reviews", status_code=201)
def create_review(r: ReviewCreate, db: Session = Depends(get_db)):
    if not (0 <= r.rating <= 5):
        raise HTTPException(status_code=400, detail="Rating must be between 0 and 5")
    rev = Review(user_id=r.user_id, property_id=r.property_id, rating=r.rating, comment=r.comment)
    db.add(rev)
    db.commit()
    # update property average rating (simple recalculation)
    avg = db.query(func.avg(Review.rating)).filter(Review.property_id == r.property_id).scalar()
    prop = db.query(Property).get(r.property_id)
    if prop:
        prop.rating = round(float(avg or 0), 1)
        db.commit()
    return {"detail": "Review created"}

# ===== ЭНДПОИНТЫ ВЕРИФИКАЦИИ =====

@app.post("/verification/upload", response_model=VerificationOut)
async def upload_verification_documents(
    document_type: str = Form(..., description="Тип документа: passport, idCard, driver"),
    document_file: UploadFile = File(..., description="Файл документа (паспорт/удостоверение)"),
    selfie_file: UploadFile = File(..., description="Селфи пользователя"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Загрузка документов для верификации личности"""
    
    # Нормализуем тип документа: принимаем как API-коды, так и локализованные значения.
    document_type_aliases = {
        "passport": "passport",
        "idcard": "idCard",
        "driver": "driver",
        "паспорт": "passport",
        "id карта": "idCard",
        "водительские права": "driver",
    }
    normalized_document_type = document_type_aliases.get(document_type.strip().lower())
    if not normalized_document_type:
        raise HTTPException(
            status_code=400, 
            detail="Недопустимый тип документа. Разрешены: passport, idCard, driver"
        )
    
    # Проверяем, что файлы являются изображениями
    if not validate_image_file(document_file):
        raise HTTPException(status_code=400, detail="Файл документа должен быть изображением (jpg, png, webp)")
    
    if not validate_image_file(selfie_file):
        raise HTTPException(status_code=400, detail="Селфи должно быть изображением (jpg, png, webp)")
    
    # Проверяем, нет ли уже активной верификации
    existing_verification = db.query(Verification).filter(
        Verification.user_id == current_user.id,
        Verification.status.in_(["pending", "approved"])
    ).first()
    
    if existing_verification:
        if existing_verification.status == "approved":
            raise HTTPException(status_code=400, detail="Пользователь уже верифицирован")
        else:
            raise HTTPException(status_code=400, detail="Верификация уже находится на рассмотрении")
    
    try:
        # Сохраняем файлы
        logging.info(f"Пользователь {current_user.email} загружает документы для верификации")
        
        document_path = await save_upload_file(document_file, "documents")
        selfie_path = await save_upload_file(selfie_file, "selfies")
        
        # Оптимизируем изображения
        full_document_path = os.path.join(os.getcwd(), document_path)
        full_selfie_path = os.path.join(os.getcwd(), selfie_path)
        
        resize_image_if_needed(full_document_path)
        resize_image_if_needed(full_selfie_path)
        
        # Создаем запись верификации
        verification = Verification(
            user_id=current_user.id,
            document_type=normalized_document_type,
            document_url=document_path,
            selfie_url=selfie_path,
            status="pending"
        )
        
        db.add(verification)
        db.commit()
        db.refresh(verification)
        
        logging.info(f"Верификация #{verification.id} создана для пользователя {current_user.email}")
        
        return verification
        
    except Exception as e:
        logging.error(f"Ошибка при загрузке верификации: {e}")
        raise HTTPException(status_code=500, detail="Ошибка при сохранении файлов")

@app.get("/verification/status", response_model=Optional[VerificationOut])
async def get_verification_status(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Получение статуса верификации текущего пользователя"""
    
    verification = db.query(Verification).filter(
        Verification.user_id == current_user.id
    ).order_by(Verification.created_at.desc()).first()
    
    return verification

@app.get("/verification/all", response_model=List[VerificationOut])
async def get_all_verifications(
    status: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Получение всех верификаций (только для администраторов)"""
    
    # Здесь можно добавить проверку прав администратора
    # if not current_user.is_admin:
    #     raise HTTPException(status_code=403, detail="Недостаточно прав")
    
    query = db.query(Verification)
    
    if status:
        query = query.filter(Verification.status == status)
    
    return query.order_by(Verification.created_at.desc()).all()

@app.get("/verification/all/detailed", response_model=List[VerificationAdminOut])
async def get_all_verifications_detailed(
        status: Optional[str] = None,
        current_user: User = Depends(get_current_user),
        db: Session = Depends(get_db)
):
    """Получение пользователей с последней верификацией (или без нее) для модерации"""
    users = db.query(User).order_by(User.created_at.desc()).all()

    result: List[VerificationAdminOut] = []
    for user in users:
        verification = db.query(Verification).filter(
            Verification.user_id == user.id
        ).order_by(Verification.created_at.desc()).first()

        current_status = verification.status if verification else "not_submitted"

        if status and current_status != status:
            continue

        result.append(
            VerificationAdminOut(
                verification_id=verification.id if verification else None,
                user_id=user.id,
                user_name=user.name,
                user_surname=user.surname,
                user_patronymic=user.patronymic,
                user_email=user.email,
                user_created_at=user.created_at,
                is_verified=user.is_verified,
                document_type=verification.document_type if verification else None,
                document_url=verification.document_url if verification else None,
                selfie_url=verification.selfie_url if verification else None,
                status=current_status,
                notes=verification.notes if verification else None,
                created_at=verification.created_at if verification else None,
                updated_at=verification.updated_at if verification else None,
            )
        )

    return result

@app.get("/admin/verifications", response_class=HTMLResponse)
def admin_verifications_page():
        """Простая веб-страница модерации верификаций"""
        return HTMLResponse(
                content="""
<!doctype html>
<html lang="ru">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Модерация верификаций</title>
    <style>
        :root {
            --bg: #f5f7fb;
            --card: #ffffff;
            --text: #1d2636;
            --muted: #6b778c;
            --ok: #1f9d55;
            --bad: #d64545;
            --line: #d8deea;
            --accent: #0d6efd;
        }
        body {
            margin: 0;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            color: var(--text);
            background: radial-gradient(circle at top right, #e8f0ff, var(--bg));
        }
        .wrap {
            max-width: 1200px;
            margin: 0 auto;
            padding: 24px;
        }
        h1 {
            margin: 0 0 16px;
        }
        .toolbar {
            display: grid;
            grid-template-columns: 1fr auto auto auto;
            gap: 10px;
            background: var(--card);
            border: 1px solid var(--line);
            border-radius: 12px;
            padding: 12px;
            margin-bottom: 16px;
        }
        .toolbar input, .toolbar select, .toolbar button {
            border: 1px solid var(--line);
            border-radius: 8px;
            padding: 10px;
            font-size: 14px;
        }
        .toolbar button {
            cursor: pointer;
            background: var(--accent);
            color: #fff;
        }
        .list {
            display: grid;
            gap: 14px;
        }
        .card {
            background: var(--card);
            border: 1px solid var(--line);
            border-radius: 14px;
            overflow: hidden;
        }
        .head {
            display: flex;
            justify-content: space-between;
            padding: 12px 14px;
            border-bottom: 1px solid var(--line);
        }
        .meta {
            padding: 12px 14px;
            color: var(--muted);
            font-size: 14px;
            display: grid;
            gap: 4px;
        }
        .images {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 8px;
            padding: 0 14px 14px;
        }
        .images img {
            width: 100%;
            border-radius: 10px;
            border: 1px solid var(--line);
            background: #eef2f8;
            min-height: 180px;
            object-fit: cover;
        }
        .actions {
            display: flex;
            gap: 8px;
            padding: 0 14px 14px;
            flex-wrap: wrap;
        }
        .actions button {
            border: 0;
            border-radius: 8px;
            padding: 10px 12px;
            color: #fff;
            cursor: pointer;
        }
        .form-grid {
            display: grid;
            gap: 8px;
            padding: 0 14px 14px;
        }
        .form-grid input,
        .form-grid textarea {
            width: 100%;
            box-sizing: border-box;
            border: 1px solid var(--line);
            border-radius: 10px;
            padding: 10px 12px;
            font-size: 14px;
            font-family: inherit;
        }
        .form-grid textarea {
            min-height: 88px;
            resize: vertical;
        }
        .approve { background: var(--ok); }
        .reject { background: var(--bad); }
        .pending { color: #b28b00; font-weight: 600; }
        .approved { color: var(--ok); font-weight: 600; }
        .rejected { color: var(--bad); font-weight: 600; }
        .error {
            margin-top: 10px;
            color: var(--bad);
            white-space: pre-wrap;
        }
        @media (max-width: 800px) {
            .toolbar { grid-template-columns: 1fr; }
            .images { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
    <div class="wrap">
        <h1>Модерация заявок на верификацию</h1>
        <div class="toolbar">
            <input id="token" placeholder="Bearer token" />
            <select id="statusFilter">
                <option value="">Все статусы</option>
                <option value="not_submitted">not_submitted</option>
                <option value="pending">pending</option>
                <option value="approved">approved</option>
                <option value="rejected">rejected</option>
            </select>
            <button onclick="loadData()">Загрузить</button>
            <button onclick="quickLogin()">Войти (email/pass)</button>
        </div>
        <div id="error" class="error"></div>
        <div id="list" class="list"></div>
    </div>

    <script>
        const apiBase = window.location.origin;

        function statusClass(status) {
            if (status === 'approved') return 'approved';
            if (status === 'rejected') return 'rejected';
            if (status === 'not_submitted') return '';
            return 'pending';
        }

        async function quickLogin() {
            const email = prompt('Email:');
            const password = prompt('Password:');
            if (!email || !password) return;

            const res = await fetch(`${apiBase}/login`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ email, password })
            });

            const body = await res.json();
            if (!res.ok) {
                document.getElementById('error').textContent = body.detail || 'Ошибка входа';
                return;
            }

            document.getElementById('token').value = body.access_token;
            loadData();
        }

        async function loadData() {
            const token = document.getElementById('token').value.trim();
            const status = document.getElementById('statusFilter').value;
            const err = document.getElementById('error');
            err.textContent = '';

            if (!token) {
                err.textContent = 'Укажите token или нажмите Войти (email/pass).';
                return;
            }

            const url = new URL(`${apiBase}/verification/all/detailed`);
            if (status) url.searchParams.set('status', status);

            const res = await fetch(url, {
                headers: { Authorization: `Bearer ${token}` }
            });
            const body = await res.json();

            if (!res.ok) {
                err.textContent = `${res.status}: ${body.detail || 'Ошибка загрузки'}`;
                return;
            }

            renderList(body, token);
        }

        function renderList(items, token) {
            const list = document.getElementById('list');
            if (!items.length) {
                list.innerHTML = '<div class="card"><div class="meta">Заявок не найдено.</div></div>';
                return;
            }

            list.innerHTML = items.map(item => {
                const docUrl = item.document_url ? `${apiBase}/${item.document_url}` : '';
                const selfieUrl = item.selfie_url ? `${apiBase}/${item.selfie_url}` : '';
                const verificationLabel = item.verification_id ? `#${item.verification_id}` : 'без заявки';
                const canModerate = !!item.verification_id;
                const fieldKey = item.user_id;

                return `
                    <div class="card">
                        <div class="head">
                            <strong>${verificationLabel} • ${item.user_name} (${item.user_email})</strong>
                            <span class="${statusClass(item.status)}">${item.status}</span>
                        </div>
                        <div class="meta">
                            <div>Пользователь создан: ${item.user_created_at}</div>
                            <div>Тип документа: ${item.document_type || '-'}</div>
                            <div>Заявка создана: ${item.created_at || '-'}</div>
                            <div>Комментарий: ${item.notes || '-'}</div>
                        </div>
                        <div class="images">
                            ${docUrl ? `<img src="${docUrl}" alt="Документ" />` : `<img alt="Документ отсутствует" />`}
                            ${selfieUrl ? `<img src="${selfieUrl}" alt="Селфи" />` : `<img alt="Селфи отсутствует" />`}
                        </div>
                        ${canModerate ? `
                        <div class="form-grid">
                            <input id="name-${fieldKey}" placeholder="Имя" value="${item.user_name || ''}" />
                            <input id="surname-${fieldKey}" placeholder="Фамилия" value="${item.user_surname || ''}" />
                            <input id="patronymic-${fieldKey}" placeholder="Отчество" value="${item.user_patronymic || ''}" />
                            <textarea id="notes-${fieldKey}" placeholder="Комментарий при отказе">${item.notes || ''}</textarea>
                        </div>
                        <div class="actions">
                            <button class="approve" onclick="updateStatus(${item.verification_id}, 'approved', ${fieldKey}, '${token}')">Одобрить</button>
                            <button class="reject" onclick="updateStatus(${item.verification_id}, 'rejected', ${fieldKey}, '${token}')">Отклонить</button>
                        </div>` : ''}
                    </div>
                `;
            }).join('');
        }

        async function updateStatus(id, status, fieldKey, token) {
            const notes = (document.getElementById(`notes-${fieldKey}`)?.value || '').trim();
            const userName = (document.getElementById(`name-${fieldKey}`)?.value || '').trim();
            const userSurname = (document.getElementById(`surname-${fieldKey}`)?.value || '').trim();
            const userPatronymic = (document.getElementById(`patronymic-${fieldKey}`)?.value || '').trim();

            if (status === 'rejected' && !notes) {
                alert('Укажите причину отказа');
                return;
            }

            const res = await fetch(`${apiBase}/verification/${id}/status`, {
                method: 'PATCH',
                headers: {
                    'Content-Type': 'application/json',
                    Authorization: `Bearer ${token}`
                },
                body: JSON.stringify({
                    status,
                    notes,
                    user_name: userName,
                    user_surname: userSurname,
                    user_patronymic: userPatronymic
                })
            });
            const body = await res.json();
            if (!res.ok) {
                alert(`${res.status}: ${body.detail || 'Ошибка обновления'}`);
                return;
            }
            loadData();
        }
    </script>
</body>
</html>
                """
        )

@app.patch("/verification/{verification_id}/status", response_model=VerificationOut)
async def update_verification_status(
    verification_id: int,
    status_update: VerificationStatusUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Обновление статуса верификации (для модераторов)"""
    
    # Здесь можно добавить проверку прав модератора
    # if not current_user.is_moderator:
    #     raise HTTPException(status_code=403, detail="Недостаточно прав")
    
    verification = db.query(Verification).filter(Verification.id == verification_id).first()
    
    if not verification:
        raise HTTPException(status_code=404, detail="Верификация не найдена")
    
    # Проверяем допустимые статусы
    allowed_statuses = {"approved", "rejected", "pending"}
    if status_update.status not in allowed_statuses:
        raise HTTPException(
            status_code=400, 
            detail=f"Недопустимый статус. Разрешены: {', '.join(allowed_statuses)}"
        )

    if status_update.status == "rejected" and not (status_update.notes or "").strip():
        raise HTTPException(status_code=400, detail="Для отказа нужен комментарий с причиной")
    
    verification.status = status_update.status
    verification.notes = status_update.notes
    
    # Если верификация одобрена, обновляем статус пользователя
    if status_update.status == "approved":
        user = db.query(User).filter(User.id == verification.user_id).first()
        if user:
            user.is_verified = True
            if status_update.user_name is not None:
                user.name = status_update.user_name.strip() or user.name
            if status_update.user_surname is not None:
                user.surname = status_update.user_surname.strip() or user.surname
            if status_update.user_patronymic is not None:
                patronymic = status_update.user_patronymic.strip()
                user.patronymic = patronymic if patronymic else None
            db.flush()
    
    db.commit()
    db.refresh(verification)
    
    logging.info(f"Верификация #{verification_id} обновлена до статуса '{status_update.status}'")
    
    return verification

# Run with: uvicorn main:app --reload