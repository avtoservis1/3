# ============================================
# XIZMAT TURLARI NARXLARINI BAZADA O'RNATISH
# ============================================
# Pastdagi PRICES lug'atida har bir xizmat turi ID'si uchun Sedan va
# Krossover narxlarini kiriting (so'mda, butun son, masalan: 150000).
#
# - Narxni hali bilmasangiz - o'sha joyda None qoldiring, u o'tkazib
#   yuboriladi va bazadagi eski qiymati o'zgarmaydi.
# - Faqat sedan narxini bilsangiz, crossover joyiga None qoldirsangiz
#   bo'ladi (aksincha ham mumkin) - ular alohida-alohida yangilanadi.
#
# ISHLATISH:
#   1) export DATABASE_URL="postgresql://user:parol@host:port/dbname"
#   2) pip install sqlalchemy psycopg2-binary   (agar hali o'rnatilmagan bo'lsa)
#   3) python set_service_type_prices.py
#
#   Skript avval nima o'zgarishini ko'rsatadi va tasdiqlashingizni so'raydi,
#   shundan keyingina bazaga yozadi.
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

# ============================================
# NARXLARNI SHU YERGA YOZING (so'mda, masalan: 150000)
# Format: ID: ("nomi - faqat sizga eslatma uchun", sedan_narxi, krossover_narxi)
# ============================================
PRICES = {
    4: ("Dvigatelni o'lik batareya bilan ishga tushirish", 130000, 130000),
    6: ("Shinalarga dam berish", 110000, 110000),
    7: ("G'ildirakni almashtirish", 140000, 140000),
    8: ("G'ildirakni ta'mirlash", 200000, 200000),
    9: ("Gi'ldirakni teshigini jgut bilan ta'miralash", 110000, 110000),
    10: ("O'g'irlikka qarshi tizimni blokdan chiqarish", 500000, 500000),
    11: ("Saqlagichni almashtirish", 110000, 110000),
    12: ("O't oldirish tizimini diagnostika qilish va sozlash", 300000, 300000),
    13: ("Eshik qulflarini ta'mirlash va sozlash", 180000, 180000),
    14: ("GRM qayishini almashtirish", 400000, 400000),
    15: ("Klapanlar qopqog'ining prokladkasini almashtirish", 400000, 400000),
    16: ("Dvigatel yostig'ini almashtirish", 350000, 350000),
    17: ("Oyna tozalagichning cho'tkalarini almashtirish", 100000, 100000),
    18: ("Qanotostini almashtirish", 250000, 250000),
    19: ("Loy sachrashidan himoya o'rnatish", 180000, 180000),
    20: ("Eshik tutqichlarini almashtirish", 200000, 200000),
    21: ("Yon oynalarni almashtirish", 350000, 350000),
    22: ("Oyna ko'targichni almashtirish", 350000, 350000),
    23: ("Bamperni almashtirish", 600000, 600000),
    24: ("GUR suyuqligini almashtirish", 200000, 200000),
    25: ("GUR qayishini almashtirish", 400000, 400000),
    27: ("GUR nasosining shlangini almashtirish", 300000, 300000),
    28: ("Antifriz va tosolni almashtirish", 200000, 200000),
    29: ("Pompani almashtirish", 500000, 500000),
    30: ("Termostatni almashtirish", 400000, 400000),
    31: ("Qisqa naychani (patrubok) almashtirish", 250000, 250000),
    32: ("Benzonasosni almashtirish", 500000, 500000),
    33: ("Dvigatel forsunkalarini almashtirish", 300000, 300000),
    34: ("Gaz yuritmasi trosini almashtirish", 250000, 250000),
    35: ("Asosiy tormoz silindrini almashtirish", 400000, 400000),
    36: ("Tormoz shlangini almashtirish", 350000, 350000),
    37: ("Tormoz diskini almashtirish", 350000, 350000),
    38: ("Tormoz suyuqligini almashtirish", 200000, 200000),
    39: ("Ort tormoz silindrini almashtirish", 400000, 400000),
    40: ("Tormoz barabanini almashtirish", 400000, 400000),
    41: ("Tormoz tizimidan qon ketish", 200000, 200000),
    42: ("Ilashish troschasini almashtirish (mexanik uzatma qutisida)", 350000, 350000),
    43: ("Yonilg'i filtrini almashtirish (tashqi)", 300000, 300000),
    44: ("Salon filtrini almashtirish", 200000, 200000),
    45: ("Havo filtrini almashtirish", 130000, 130000),
    46: ("Tashqi granatani almashtirish", 350000, 350000),
    47: ("Rul tyagasini almashtirish", 350000, 350000),
    48: ("Sharli tayanchni almashtirish", 350000, 350000),
    49: ("Stabilizator ustunlarini almashtirish", 300000, 300000),
    50: ("Tashqi granataning changtutgichini almashtirish", 350000, 350000),
    51: ("Rulda uchliklarini almashtirish", 350000, 350000),
    52: ("Stupitsani (yig'ma olida) almashtirish", 400000, 400000),
    53: ("Ort va old osma amortizatorining prujinalarini almashtirish", 400000, 400000),
    54: ("Ort va old osma amortizatorini yig'ma holatida almashtirish", 400000, 400000),
    55: ("Yuqori kuchlanish simlarini almashtirish", 200000, 200000),
    56: ("Generator qayishini almashtirish", 300000, 300000),
    57: ("Generatorni almashtirish", 450000, 450000),
    58: ("Datchiklarni almashtirish", 250000, 250000),
    59: ("Saqlagich tashlab yuborsa", 200000, 200000),
    61: ("Oyna ko'targichga manbani ulash", 350000, 350000),
    62: ("Radiator ventilyatoriga manbani ulash", 250000, 250000),
    63: ("Kapot qismga namlik tushishi", 500000, 500000),
    64: ("Kapot elektronikani almashtirish", 1500000, 1500000),
    65: ("Panel osti elektronikani almashtirish", 1700000, 1700000),
    66: ("Tramblerni almashtirish", 300000, 300000),
    67: ("Starterni almashtirish", 300000, 300000),
    68: ("Orqa chiroq lampalarini almashtirish", 100000, 100000),
    69: ("Old faraning lampalarini almashtirish", 100000, 100000),
    70: ("Tuman faralarining lampalarini almashtirish", 100000, 100000),
    71: ("Klaksonni almashtirish", 100000, 100000),
    72: ("Old oynani yuvish forsunkalarini almashtirish", 100000, 100000),
    73: ("Raqam belgisini yorituvchi lampalarini almashtirish", 100000, 100000),
    74: ("Akkumulyatorni quvvatlab ishga tushirish", 130000, 130000),
    75: ("G'ildirakni zapaska bilan almashtirish", 140000, 140000),
    78: ("Shinani havo bilan to'ldirish", 110000, 110000),
    79: ("Shinamontaj / shinaning kichik ta'miri", 200000, 200000),
    80: ("Shina teshigini ta'mirlash", 110000, 110000),
    81: ("Zajiganiyeni sozlash", 300000, 300000),
    82: ("Old/Orqa stoykani almashtirish (osma)", 400000, 400000),
    83: ("Harorat datchigini almashtirish", 200000, 200000),
    84: ("GUR moyini almashtirish", 200000, 200000),
    85: ("Signalni almashtirish", 100000, 100000),
    86: ("Oldi va orqa osma stoykalari prujinalarini almashtirish", 400000, 400000),
    87: ("Kapot ostidagi namlikni yo'qotish", 500000, 500000),
    88: ("Signalizatsiyani blokdan chiqarish", 500000, 500000),
}


def main():
    to_update = {k: v for k, v in PRICES.items() if v[1] is not None or v[2] is not None}
    if not to_update:
        print("PRICES lug'atida hech qanday narx kiritilmagan (hammasi None).")
        print("Avval yuqoridagi ro'yxatga narxlarni yozib chiqing, keyin qayta ishga tushiring.")
        return

    with engine.connect() as conn:
        # Bazadagi haqiqiy nomlarni tekshirish uchun olib kelamiz
        rows = conn.execute(text(
            "SELECT id, name FROM service_types WHERE id = ANY(:ids)"
        ), {"ids": list(to_update.keys())}).fetchall()
        db_names = {r[0]: r[1] for r in rows}

        missing = [tid for tid in to_update if tid not in db_names]
        if missing:
            print("DIQQAT: quyidagi ID'lar bazada topilmadi (o'chirilgan bo'lishi mumkin), o'tkazib yuborildi:")
            for tid in missing:
                print(f"  - ID {tid}: {to_update[tid][0]}")
            print()

        print("Quyidagi o'zgarishlar amalga oshiriladi:\n")
        print(f"{'ID':<5} {'Bazadagi nomi':<55} {'Sedan':<12} {'Krossover'}")
        print("-" * 90)
        applied = {}
        for tid, (ref_name, sedan, crossover) in to_update.items():
            if tid not in db_names:
                continue
            applied[tid] = (sedan, crossover)
            sedan_text = f"{sedan} so'm" if sedan is not None else "-"
            crossover_text = f"{crossover} so'm" if crossover is not None else "-"
            print(f"{tid:<5} {db_names[tid]:<55} {sedan_text:<12} {crossover_text}")

        if not applied:
            print("\nHech narsa yangilanmadi.")
            return

        confirm = input(f"\n{len(applied)} ta xizmat turining narxini yangilashni tasdiqlaysizmi? (ha/yo'q): ").strip().lower()
        if confirm not in ("ha", "h", "y", "yes"):
            print("Bekor qilindi. Bazaga hech narsa yozilmadi.")
            return

        for tid, (sedan, crossover) in applied.items():
            fields = {}
            if sedan is not None:
                fields["price_sedan"] = sedan
                fields["price"] = sedan  # eskirgan maydon - orqaga moslik uchun
            if crossover is not None:
                fields["price_crossover"] = crossover
            set_clause = ", ".join(f"{col} = :{col}" for col in fields)
            fields["tid"] = tid
            conn.execute(text(f"UPDATE service_types SET {set_clause} WHERE id = :tid"), fields)
        conn.commit()

        print(f"\nTayyor! {len(applied)} ta xizmat turining narxi bazada yangilandi.")


if __name__ == "__main__":
    main()