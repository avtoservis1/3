# ============================================
# BAZANI TOZALASH: foydalanuvchilar, servis egalari, buyurtmalar va
# statistikaga oid barcha ma'lumotlarni o'chiradi.
#
# TEGILMAYDIGAN JADVALLAR (o'zgarishsiz qoladi):
#   - service_types      (Xizmat turlari - nomi, RASMI va SEDAN/KROSSOVER narxlari)
#   - pricing_settings    (Evakuator/benzin uchun global narx sozlamalari)
#   - partner_locations   (Admin qo'shgan moyka/zapravka manzillari)
#
# O'CHIRILADIGAN JADVALLAR:
#   - chat_messages, reviews, notifications, favorites, services_offered,
#     orders, cars, services (servis egalarining biznes profillari),
#     otp_codes, users
#
# DIQQAT: bu amalni ORQAGA QAYTARIB BO'LMAYDI. Ishga tushirishdan oldin
# bazadan zaxira nusxa (backup) olib qo'yish tavsiya etiladi.
#
# ISHLATISH:
#   export DATABASE_URL="postgresql://user:parol@host:port/dbname"
#   pip install sqlalchemy psycopg2-binary
#   python reset_users_and_orders.py
#
#   Skript avval har bir jadvaldagi qatorlar sonini ko'rsatadi va aniq
#   tasdiqlash so'zini kiritishingizni so'raydi - shundan keyingina o'chiradi.
# ============================================

import os
import sys

from sqlalchemy import create_engine, text

DATABASE_URL = "postgresql://postgres:UnZarMtKfsiaECElDFHhaQUDoHgnbyVM@sakura.proxy.rlwy.net:16523/railway"

if not DATABASE_URL:
    print("XATOLIK: DATABASE_URL environment o'zgaruvchisi o'rnatilmagan.")
    print('Masalan: export DATABASE_URL="postgresql://user:parol@host:port/dbname"')
    sys.exit(1)

if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

engine = create_engine(DATABASE_URL, pool_pre_ping=True)

# Bog'liqlik tartibida (avval "bola" jadvallar, keyin "ota" jadvallar) -
# aks holda FOREIGN KEY xatosi chiqadi.
TABLES_TO_CLEAR = [
    "chat_messages",
    "reviews",
    "notifications",
    "favorites",
    "services_offered",
    "orders",
    "cars",
    "services",
    "otp_codes",
    "users",
]

# Faqat ma'lumot uchun ko'rsatiladi - bularga TEGILMAYDI.
PRESERVED_TABLES = ["service_types", "pricing_settings", "partner_locations"]

CONFIRM_PHRASE = "ha"


def table_count(conn, table):
    return conn.execute(text(f"SELECT COUNT(*) FROM {table}")).scalar()


def main():
    with engine.connect() as conn:
        print("Hozirgi holat:\n")
        print("O'CHIRILADIGAN jadvallar:")
        total_to_delete = 0
        for t in TABLES_TO_CLEAR:
            c = table_count(conn, t)
            total_to_delete += c
            print(f"  - {t:<20} {c} ta yozuv")

        print("\nTEGILMAYDIGAN jadvallar (o'zgarishsiz qoladi):")
        for t in PRESERVED_TABLES:
            try:
                c = table_count(conn, t)
                print(f"  - {t:<20} {c} ta yozuv")
            except Exception:
                print(f"  - {t:<20} (jadval topilmadi, o'tkazib yuborildi)")

        if total_to_delete == 0:
            print("\nO'chiriladigan jadvallarda hozircha hech qanday yozuv yo'q.")
            return

        print(f"\nJami o'chiriladigan yozuvlar: {total_to_delete}")
        print("\nDIQQAT: bu amalni ORQAGA QAYTARIB BO'LMAYDI!")
        answer = input(
            f'Davom etish uchun aniq shu so\'zni yozing: "{CONFIRM_PHRASE}"\n> '
        ).strip()
        if answer != CONFIRM_PHRASE:
            print("Bekor qilindi. Bazaga hech narsa tegilmadi.")
            return

        try:
            for t in TABLES_TO_CLEAR:
                result = conn.execute(text(f"DELETE FROM {t}"))
                print(f"  o'chirildi: {t} ({result.rowcount} ta yozuv)")

            # Postgres: id ketma-ketligini 1 dan qayta boshlash (ixtiyoriy,
            # xatolik chiqsa e'tiborsiz qoldiriladi - masalan Postgres bo'lmasa).
            for t in TABLES_TO_CLEAR:
                try:
                    conn.execute(text(
                        f"ALTER SEQUENCE {t}_id_seq RESTART WITH 1"
                    ))
                except Exception:
                    pass

            conn.commit()
        except Exception as e:
            conn.rollback()
            print(f"\nXATOLIK yuz berdi, o'zgarishlar bekor qilindi (rollback): {e}")
            sys.exit(1)

        print("\nTayyor! Foydalanuvchilar, servis egalari, buyurtmalar va bog'liq "
              "barcha ma'lumotlar tozalandi.")
        print("Xizmat turlari (nomi, rasmi, sedan/krossover narxlari) o'zgarishsiz qoldi.")


if __name__ == "__main__":
    main()