-- =====================================================================
-- clean_export_hscode.sql  (มาตรฐานคลีนข้อมูล v1.2 สำหรับ SQLite)
-- ไฟล์ต้นฉบับ : exportvalueperhscode64.csv  (มูลค่าส่งออกรายเดือนตามพิกัด HS ปี พ.ศ. 2564)
-- ไฟล์ผลลัพธ์ : exportvalueperhscode64_clean.csv (UTF-8 มี BOM, ขึ้นบรรทัดใหม่แบบ CRLF)
-- =====================================================================

-- ---------------------------------------------------------------------
-- ข้อ 0: ตารางข้อมูลดิบ (ทุกคอลัมน์เป็น TEXT เพื่อไม่ให้เลขศูนย์นำหน้าหาย)
--   year_be   = ปีแม่แบบ              month_no   = เดือนแม่แบบ
--   hs8       = พิกัดศุลกากร 8 หลัก   stat_code  = รหัสสถิติ
--   desc_th   = คำอธิบายไทย           desc_en    = คำอธิบาย (อังกฤษ)
--   value_thb = มูลค่าส่งออกเงินบาท
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS export_raw (
  year_be TEXT, month_no TEXT, hs8 TEXT, stat_code TEXT,
  desc_th TEXT, desc_en TEXT, value_thb TEXT
);

-- ---------------------------------------------------------------------
-- ข้อ 1: ทำความสะอาดข้อความรายแถว -> ตาราง stg_clean
--   1.1 คอลัมน์รหัส (hs8, stat_code): ตัดช่องว่างหัวท้าย (ต้นฉบับมีช่องว่างนำหน้าทุกแถว)
--       เก็บเป็น TEXT ต่อไป เพื่อรักษาเลขศูนย์นำหน้า
--   1.2 คอลัมน์ชื่อ (desc_th, desc_en):
--       - แปลง non-breaking space (U+00A0) เป็นช่องว่างปกติ
--       - ตัดช่องว่างหัวท้าย
--       - ยุบช่องว่างซ้อนกันให้เหลือช่องเดียว (replace '  ' -> ' ' ซ้ำ 5 ชั้น
--         รองรับช่องว่างติดกันได้ยาวถึง 32 ตัว ; ข้อมูลนี้ยาวสุดแค่ 12)
--   1.3 แก้อักขระต่างสคริปต์ที่ปนในชื่ออังกฤษ (ตามดุลพินิจ):
--       - 'ฐ C'  -> '°C'  (อุณหภูมิ "below 4 ฐ C")
--       - 'หรือ' -> 'or'  ("8701.24 หรือ 8701.29")
--   1.4 value_thb แปลงเป็นจำนวนเต็ม (INTEGER) ; ไม่ตัดทิ้งค่าศูนย์/ค่าเล็กมาก
--   เก็บลำดับแถวเดิมไว้ใน rid
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS stg_clean;
CREATE TABLE stg_clean AS
SELECT
  rowid AS rid,
  CAST(trim(year_be)  AS INTEGER) AS year_be,
  CAST(trim(month_no) AS INTEGER) AS month_no,
  trim(hs8)       AS hs8,
  trim(stat_code) AS stat_code,
  -- ชื่อไทย: nbsp -> space, trim, ยุบช่องว่างซ้อน
  replace(replace(replace(replace(replace(
    trim(replace(desc_th, char(160), ' ')),
    '  ',' '),'  ',' '),'  ',' '),'  ',' '),'  ',' ') AS desc_th,
  -- ชื่ออังกฤษ: ทำเหมือนกัน แล้วแก้อักขระต่างสคริปต์ (ข้อ 1.3)
  replace(replace(
    replace(replace(replace(replace(replace(
      trim(replace(desc_en, char(160), ' ')),
      '  ',' '),'  ',' '),'  ',' '),'  ',' '),'  ',' '),
    'ฐ C','°C'),
    'หรือ','or') AS desc_en,
  CAST(trim(value_thb) AS INTEGER) AS value_thb
FROM export_raw;

-- ---------------------------------------------------------------------
-- ข้อ 2: รวมชื่ออังกฤษที่ต่างกันเฉพาะตัวพิมพ์เล็ก-ใหญ่ -> ตาราง en_fix
--   เฉพาะกลุ่มที่ lower(ชื่อ) เหมือนกันแต่เขียนต่างกัน (เช่น 'OTHER' / 'Other' / 'other')
--   ให้เป็น sentence case (อักษรแรกตัวใหญ่ ที่เหลือตัวเล็ก)
--   ชื่อที่ไม่อยู่ในกลุ่มซ้ำ ไม่แตะต้อง (ไม่แปลงทั้งคอลัมน์เป็นตัวพิมพ์เล็ก)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS en_fix;
CREATE TABLE en_fix AS
SELECT DISTINCT desc_en AS old_name,
       upper(substr(desc_en,1,1)) || lower(substr(desc_en,2)) AS new_name
FROM stg_clean
WHERE lower(desc_en) IN (
  SELECT lower(desc_en) FROM stg_clean
  GROUP BY lower(desc_en) HAVING COUNT(DISTINCT desc_en) > 1
);

UPDATE stg_clean
SET desc_en = (SELECT new_name FROM en_fix WHERE old_name = stg_clean.desc_en)
WHERE desc_en IN (SELECT old_name FROM en_fix);

-- ---------------------------------------------------------------------
-- ข้อ 3: รวมแถวที่คีย์ซ้ำ (ปี, เดือน, พิกัด HS, รหัสสถิติ) ด้วย SUM -> ตาราง export_clean
--   ไม่ลบแถวทิ้ง ; ชื่อใช้ MIN() (ตรวจแล้วว่าแถวที่ซ้ำคีย์มีชื่อเหมือนกัน)
--   คงลำดับตามแถวแรกที่พบของแต่ละคีย์ (MIN(rid))
--   แถวมูลค่า 0 และมูลค่า < 1,000 บาท ยังเก็บไว้ ให้กรองตอนวิเคราะห์เท่านั้น
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS export_clean;
CREATE TABLE export_clean AS
SELECT year_be, month_no, hs8, stat_code,
       MIN(desc_th) AS desc_th, MIN(desc_en) AS desc_en,
       SUM(value_thb) AS value_thb
FROM stg_clean
GROUP BY year_be, month_no, hs8, stat_code
ORDER BY MIN(rid);

-- ---------------------------------------------------------------------
-- ข้อ 4: ตรวจสอบหลังคลีน (ผลต้องเป็นไปตามที่คาด)
--   - rows_raw - rows_clean ต้องเท่ากับจำนวนแถวที่ถูกรวมจากคีย์ซ้ำเท่านั้น
--   - sum_raw ต้องเท่ากับ sum_clean (มูลค่ารวมไม่เปลี่ยน)
--   - ที่เหลือต้องเป็น 0 ทั้งหมด
-- ---------------------------------------------------------------------
SELECT 'rows_raw' AS check_name, COUNT(*) AS result FROM export_raw
UNION ALL SELECT 'rows_clean', COUNT(*) FROM export_clean
UNION ALL SELECT 'sum_raw',   SUM(CAST(trim(value_thb) AS INTEGER)) FROM export_raw
UNION ALL SELECT 'sum_clean', SUM(value_thb) FROM export_clean
UNION ALL SELECT 'dup_keys_left', COUNT(*) FROM (
  SELECT 1 FROM export_clean GROUP BY year_be, month_no, hs8, stat_code HAVING COUNT(*) > 1)
UNION ALL SELECT 'bad_code_format', COUNT(*) FROM export_clean
  WHERE length(hs8) <> 8 OR length(stat_code) <> 3
     OR hs8 GLOB '*[^0-9]*' OR stat_code GLOB '*[^0-9]*'
UNION ALL SELECT 'text_space_issues', COUNT(*) FROM export_clean
  WHERE desc_th <> trim(desc_th) OR desc_en <> trim(desc_en)
     OR desc_th LIKE '%  %' OR desc_en LIKE '%  %'
     OR desc_th LIKE '%' || char(160) || '%' OR desc_en LIKE '%' || char(160) || '%'
UNION ALL SELECT 'thai_chars_in_en', COUNT(*) FROM export_clean
  WHERE desc_en GLOB '*[ก-๙]*'
UNION ALL SELECT 'en_case_variant_groups', COUNT(*) FROM (
  SELECT 1 FROM export_clean GROUP BY lower(desc_en) HAVING COUNT(DISTINCT desc_en) > 1);

-- ---------------------------------------------------------------------
-- ข้อ 5: ส่งออกไฟล์ CSV (หัวคอลัมน์ภาษาไทยเหมือนต้นฉบับ)
--   ใน sqlite3 CLI:  .headers on / .mode csv / .output exportvalueperhscode64_clean.csv
--   แล้วรัน SELECT ด้านล่าง  (CLI ขึ้นบรรทัดใหม่เป็น LF ต้องแปลงเป็น CRLF
--   และเติม BOM ภายหลัง เพื่อให้ได้ UTF-8 with BOM + CRLF ตามมาตรฐาน)
-- ---------------------------------------------------------------------
SELECT year_be AS "ปีแม่แบบ", month_no AS "เดือนแม่แบบ",
       hs8 AS "พิกัดศุลกากร 8 หลัก", stat_code AS "รหัสสถิติ",
       desc_th AS "คำอธิบายไทย", desc_en AS "คำอธิบาย",
       value_thb AS "มูลค่าส่งออกเงินบาท"
FROM export_clean;
