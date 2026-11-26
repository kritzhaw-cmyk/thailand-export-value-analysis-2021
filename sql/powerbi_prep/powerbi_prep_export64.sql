-- =====================================================================
-- powerbi_prep_export64.sql  (SQLite 3.35 ขึ้นไป เพราะใช้ฟังก์ชัน sqrt และ window function)
-- วัตถุประสงค์: เตรียมตารางสำหรับนำเข้า Power BI (Star Schema) จากข้อมูลที่คลีนแล้ว
-- ข้อมูลตั้งต้น: ตาราง export_clean (ผลลัพธ์จาก clean_export_hscode.sql)
--   ถ้าเปิดฐานข้อมูลใหม่ ให้นำเข้า exportvalueperhscode64_clean.csv เป็นตาราง export_clean
--   โดยคอลัมน์ต้องชื่อ: year_be, month_no, hs8, stat_code, desc_th, desc_en, value_thb
--
-- ตารางที่ได้ (ส่งออกเป็น CSV ไปโหลดใน Power BI):
--   1) dim_hs_section       หมวดพิกัดศุลกากร (Section 21 หมวด)
--   2) dim_hs_chapter       หมวดสินค้าระดับ Chapter 2 หลักแรกของ HS พร้อมชื่อไทย/อังกฤษ
--   3) dim_month            ตารางเดือน/ไตรมาส/วันที่
--   4) dim_product          สินค้าแต่ละรายการ (พิกัด 8 หลัก + รหัสสถิติ)
--   5) fact_export_monthly  ตารางข้อเท็จจริง: มูลค่าส่งออกรายเดือนรายสินค้า
--   6) summary_chapter_stability  สรุปราย Chapter: สัดส่วน ความสม่ำเสมอ เดือนสูงสุด/ต่ำสุด
--   7) summary_month_total        สรุปรายเดือน: มูลค่ารวม อัตราเปลี่ยนแปลงจากเดือนก่อน
-- =====================================================================

-- ---------------------------------------------------------------------
-- ข้อ 1: dim_hs_section  แบ่ง Chapter ออกเป็น 21 หมวดตามโครงสร้างระบบ HS
--   ช่วง chapter_from-chapter_to ใช้จับคู่กับเลข 2 หลักแรกของพิกัด
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS dim_hs_section;
CREATE TABLE dim_hs_section (
  section_no INTEGER PRIMARY KEY, chapter_from INTEGER, chapter_to INTEGER,
  section_name_en TEXT, section_name_th TEXT
);
INSERT INTO dim_hs_section VALUES
  (1,1,5,'Live animals; animal products','สัตว์มีชีวิตและผลิตภัณฑ์จากสัตว์'),
  (2,6,14,'Vegetable products','ผลิตภัณฑ์จากพืช'),
  (3,15,15,'Animal or vegetable fats and oils','ไขมันและน้ำมันจากสัตว์หรือพืช'),
  (4,16,24,'Prepared foodstuffs; beverages; tobacco','อาหารปรุงแต่ง เครื่องดื่ม ยาสูบ'),
  (5,25,27,'Mineral products','ผลิตภัณฑ์แร่ธาตุและเชื้อเพลิง'),
  (6,28,38,'Chemical products','เคมีภัณฑ์'),
  (7,39,40,'Plastics and rubber','พลาสติกและยาง'),
  (8,41,43,'Hides, skins, leather, furskins','หนังและผลิตภัณฑ์หนัง'),
  (9,44,46,'Wood, cork, plaiting materials','ไม้ ไม้ก๊อก วัสดุถักสาน'),
  (10,47,49,'Pulp, paper, printed matter','เยื่อไม้ กระดาษ สิ่งพิมพ์'),
  (11,50,63,'Textiles and textile articles','สิ่งทอและเครื่องนุ่งห่ม'),
  (12,64,67,'Footwear, headgear, umbrellas','รองเท้า หมวก ร่ม'),
  (13,68,70,'Stone, ceramic, glass articles','ของจากหิน เซรามิก แก้ว'),
  (14,71,71,'Pearls, precious stones and metals','อัญมณีและโลหะมีค่า'),
  (15,72,83,'Base metals and articles thereof','โลหะสามัญและของที่ทำด้วยโลหะสามัญ'),
  (16,84,85,'Machinery and electrical equipment','เครื่องจักร เครื่องใช้ไฟฟ้า อิเล็กทรอนิกส์'),
  (17,86,89,'Vehicles, aircraft, vessels','ยานพาหนะ อากาศยาน เรือ'),
  (18,90,92,'Optical, medical instruments; clocks; music','เครื่องมือแสง การแพทย์ นาฬิกา เครื่องดนตรี'),
  (19,93,93,'Arms and ammunition','อาวุธและกระสุน'),
  (20,94,96,'Miscellaneous manufactured articles','ของเบ็ดเตล็ดที่ผลิตขึ้น'),
  (21,97,99,'Works of art; special provisions','งานศิลปะและรหัสพิเศษ');

-- ---------------------------------------------------------------------
-- ข้อ 2: dim_hs_chapter  ชื่อ Chapter (เลข 2 หลักแรกของพิกัด) + หมวดที่สังกัด
--   hs_chapter เก็บเป็น TEXT เพื่อรักษาเลขศูนย์นำหน้า เช่น '08'
--   (ชื่อไทยเป็นการสรุปโดยย่อ ควรเทียบกับตารางพิกัดอัตราศุลกากรทางการก่อนนำไปอ้างอิง)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_chapter_names;
CREATE TABLE tmp_chapter_names (hs_chapter TEXT, name_en TEXT, name_th TEXT);
INSERT INTO tmp_chapter_names VALUES
  ('01','Live animals','สัตว์มีชีวิต'),
  ('02','Meat and edible meat offal','เนื้อสัตว์และส่วนที่บริโภคได้'),
  ('03','Fish, crustaceans, molluscs','ปลา สัตว์น้ำจำพวกกุ้งปูและหอย'),
  ('04','Dairy, eggs, honey','ผลิตภัณฑ์นม ไข่ น้ำผึ้ง'),
  ('05','Other animal products','ผลิตภัณฑ์จากสัตว์อื่น ๆ'),
  ('06','Live trees, plants, flowers','ต้นไม้ ไม้ดอก'),
  ('07','Edible vegetables','ผักและรากพืชที่บริโภคได้'),
  ('08','Edible fruit and nuts','ผลไม้และถั่ว'),
  ('09','Coffee, tea, spices','กาแฟ ชา เครื่องเทศ'),
  ('10','Cereals','ธัญพืช (รวมข้าว)'),
  ('11','Milling products, malt, starch','ผลิตภัณฑ์โม่สี มอลต์ แป้ง'),
  ('12','Oil seeds and misc grains','เมล็ดพืชน้ำมัน'),
  ('13','Lac, gums, resins','ครั่ง ยางไม้ ยางเหนียว'),
  ('14','Vegetable plaiting materials','วัสดุจากพืชใช้ถักสาน'),
  ('15','Animal or vegetable fats and oils','ไขมันและน้ำมันจากสัตว์หรือพืช'),
  ('16','Preparations of meat, fish','อาหารสำเร็จรูปจากเนื้อ ปลา สัตว์น้ำ'),
  ('17','Sugars and confectionery','น้ำตาลและขนมที่ทำจากน้ำตาล'),
  ('18','Cocoa and preparations','โกโก้และผลิตภัณฑ์'),
  ('19','Preparations of cereals, flour, pastry','ผลิตภัณฑ์จากธัญพืช แป้ง ขนมอบ'),
  ('20','Preparations of vegetables, fruit','ผลิตภัณฑ์จากผักและผลไม้'),
  ('21','Misc edible preparations','อาหารปรุงแต่งเบ็ดเตล็ด'),
  ('22','Beverages, spirits, vinegar','เครื่องดื่ม สุรา น้ำส้มสายชู'),
  ('23','Food industry residues; animal feed','กากจากอุตสาหกรรมอาหาร อาหารสัตว์'),
  ('24','Tobacco','ยาสูบ'),
  ('25','Salt, sulphur, earths, stone, cement','เกลือ กำมะถัน ดิน หิน ปูน'),
  ('26','Ores, slag and ash','แร่ ตะกรัน เถ้า'),
  ('27','Mineral fuels and oils','เชื้อเพลิงแร่และน้ำมัน'),
  ('28','Inorganic chemicals','เคมีภัณฑ์อนินทรีย์'),
  ('29','Organic chemicals','เคมีภัณฑ์อินทรีย์'),
  ('30','Pharmaceutical products','ผลิตภัณฑ์เภสัชกรรม'),
  ('31','Fertilisers','ปุ๋ย'),
  ('32','Tanning and dyeing extracts, paints','สารสกัดฟอกหนังและย้อมสี สี'),
  ('33','Essential oils, perfumery, cosmetics','น้ำมันหอมระเหย น้ำหอม เครื่องสำอาง'),
  ('34','Soap, waxes, candles','สบู่ แว็กซ์ เทียน'),
  ('35','Albuminoidal substances, glues, enzymes','สารโปรตีน กาว เอนไซม์'),
  ('36','Explosives, pyrotechnics, matches','วัตถุระเบิด พลุ ไม้ขีดไฟ'),
  ('37','Photographic goods','สินค้าถ่ายภาพ'),
  ('38','Misc chemical products','ผลิตภัณฑ์เคมีเบ็ดเตล็ด'),
  ('39','Plastics and articles thereof','พลาสติกและของที่ทำด้วยพลาสติก'),
  ('40','Rubber and articles thereof','ยางและของที่ทำด้วยยาง'),
  ('41','Raw hides, skins and leather','หนังดิบและหนังฟอก'),
  ('42','Articles of leather; handbags','ของที่ทำด้วยหนัง กระเป๋า'),
  ('43','Furskins and artificial fur','หนังขนสัตว์และขนสัตว์เทียม'),
  ('44','Wood and articles of wood','ไม้และของที่ทำด้วยไม้'),
  ('45','Cork and articles of cork','ไม้ก๊อกและของที่ทำด้วยไม้ก๊อก'),
  ('46','Articles of plaiting materials','ของที่ทำด้วยวัสดุถักสาน'),
  ('47','Pulp of wood','เยื่อไม้'),
  ('48','Paper and paperboard','กระดาษและกระดาษแข็ง'),
  ('49','Printed books and newspapers','หนังสือและสิ่งพิมพ์'),
  ('50','Silk','ไหม'),
  ('51','Wool and animal hair','ขนแกะและขนสัตว์'),
  ('52','Cotton','ฝ้าย'),
  ('53','Other vegetable textile fibres','เส้นใยพืชอื่น ๆ'),
  ('54','Man-made filaments','เส้นใยประดิษฐ์ใยยาว'),
  ('55','Man-made staple fibres','เส้นใยประดิษฐ์ใยสั้น'),
  ('56','Wadding, felt, nonwovens, cordage','ใยอัด สักหลาด ผ้าไม่ถักไม่ทอ เชือก'),
  ('57','Carpets and floor coverings','พรมและสิ่งทอปูพื้น'),
  ('58','Special woven fabrics','ผ้าทอพิเศษ'),
  ('59','Coated or laminated textile fabrics','ผ้าเคลือบหรืออาบ'),
  ('60','Knitted or crocheted fabrics','ผ้าถักนิตหรือโครเชต์'),
  ('61','Apparel, knitted or crocheted','เสื้อผ้าสำเร็จรูป (ถักนิตหรือโครเชต์)'),
  ('62','Apparel, not knitted or crocheted','เสื้อผ้าสำเร็จรูป (ไม่ถักนิต)'),
  ('63','Other made-up textile articles','สิ่งทอสำเร็จรูปอื่น ๆ'),
  ('64','Footwear','รองเท้า'),
  ('65','Headgear','หมวก'),
  ('66','Umbrellas, walking sticks','ร่ม ไม้เท้า'),
  ('67','Prepared feathers; artificial flowers','ขนนกปรุงแต่ง ดอกไม้เทียม'),
  ('68','Articles of stone, plaster, cement','ของที่ทำด้วยหิน ปูนปลาสเตอร์ ซีเมนต์'),
  ('69','Ceramic products','ผลิตภัณฑ์เซรามิก'),
  ('70','Glass and glassware','แก้วและเครื่องแก้ว'),
  ('71','Pearls, gems, precious metals, jewellery','ไข่มุก อัญมณี โลหะมีค่า เครื่องประดับ'),
  ('72','Iron and steel','เหล็กและเหล็กกล้า'),
  ('73','Articles of iron or steel','ของที่ทำด้วยเหล็กหรือเหล็กกล้า'),
  ('74','Copper and articles thereof','ทองแดงและของที่ทำด้วยทองแดง'),
  ('75','Nickel and articles thereof','นิกเกิลและของที่ทำด้วยนิกเกิล'),
  ('76','Aluminium and articles thereof','อะลูมิเนียมและของที่ทำด้วยอะลูมิเนียม'),
  ('77','Reserved for future use','สงวนไว้'),
  ('78','Lead and articles thereof','ตะกั่วและของที่ทำด้วยตะกั่ว'),
  ('79','Zinc and articles thereof','สังกะสีและของที่ทำด้วยสังกะสี'),
  ('80','Tin and articles thereof','ดีบุกและของที่ทำด้วยดีบุก'),
  ('81','Other base metals; cermets','โลหะสามัญอื่น ๆ'),
  ('82','Tools, cutlery of base metal','เครื่องมือ ช้อนส้อมมีดที่ทำด้วยโลหะสามัญ'),
  ('83','Misc articles of base metal','ของเบ็ดเตล็ดที่ทำด้วยโลหะสามัญ'),
  ('84','Machinery and mechanical appliances (incl. computers)','เครื่องจักรและเครื่องใช้กลไก (รวมคอมพิวเตอร์)'),
  ('85','Electrical machinery and equipment','เครื่องจักรและอุปกรณ์ไฟฟ้า อิเล็กทรอนิกส์'),
  ('86','Railway locomotives and rolling stock','รถไฟและรถราง'),
  ('87','Vehicles other than railway','ยานบก (รถยนต์ จักรยานยนต์) และส่วนประกอบ'),
  ('88','Aircraft and spacecraft','อากาศยาน'),
  ('89','Ships and boats','เรือและสิ่งก่อสร้างลอยน้ำ'),
  ('90','Optical, medical and precision instruments','เครื่องมือทางแสง การแพทย์ และเครื่องมือวัดละเอียด'),
  ('91','Clocks and watches','นาฬิกา'),
  ('92','Musical instruments','เครื่องดนตรี'),
  ('93','Arms and ammunition','อาวุธและกระสุน'),
  ('94','Furniture, bedding, lamps','เฟอร์นิเจอร์ เครื่องนอน โคมไฟ'),
  ('95','Toys, games, sports equipment','ของเล่น เกม อุปกรณ์กีฬา'),
  ('96','Misc manufactured articles','ของเบ็ดเตล็ดที่ผลิตขึ้น'),
  ('97','Works of art, antiques','งานศิลปะ ของสะสม ของเก่า'),
  ('98','Special classification provisions','รหัสพิเศษตามพิกัด'),
  ('99','Special classification provisions (national)','รหัสพิเศษตามพิกัด (ระดับประเทศ)');

DROP TABLE IF EXISTS dim_hs_chapter;
CREATE TABLE dim_hs_chapter AS
SELECT n.hs_chapter, n.name_en AS chapter_name_en, n.name_th AS chapter_name_th,
       s.section_no, s.section_name_en, s.section_name_th
FROM tmp_chapter_names n
JOIN dim_hs_section s
  ON CAST(n.hs_chapter AS INTEGER) BETWEEN s.chapter_from AND s.chapter_to
ORDER BY n.hs_chapter;

-- ---------------------------------------------------------------------
-- ข้อ 3: dim_month  ตารางเดือน (ข้อมูลชุดนี้เป็นปี พ.ศ. 2564 = ค.ศ. 2021)
--   ym_key        = ปี ค.ศ.*100 + เดือน เช่น 202101 ใช้เป็นคีย์เชื่อมกับ fact
--   month_start   = วันที่ 1 ของเดือน (ใช้เป็นแกนเวลาใน Power BI)
--   days_in_month = จำนวนวันในเดือน ใช้ปรับมูลค่าเป็นต่อวัน (ก.พ. มีแค่ 28 วัน)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_month_names;
CREATE TABLE tmp_month_names (month_no INTEGER, month_name_th TEXT, month_abbr_en TEXT);
INSERT INTO tmp_month_names VALUES
  (1,'มกราคม','Jan'),
  (2,'กุมภาพันธ์','Feb'),
  (3,'มีนาคม','Mar'),
  (4,'เมษายน','Apr'),
  (5,'พฤษภาคม','May'),
  (6,'มิถุนายน','Jun'),
  (7,'กรกฎาคม','Jul'),
  (8,'สิงหาคม','Aug'),
  (9,'กันยายน','Sep'),
  (10,'ตุลาคม','Oct'),
  (11,'พฤศจิกายน','Nov'),
  (12,'ธันวาคม','Dec');

DROP TABLE IF EXISTS dim_month;
CREATE TABLE dim_month AS
SELECT ((SELECT MIN(CAST(year_be AS INTEGER)) FROM export_clean) - 543) * 100 + month_no AS ym_key,
       (SELECT MIN(CAST(year_be AS INTEGER)) FROM export_clean) AS year_be,
       (SELECT MIN(CAST(year_be AS INTEGER)) FROM export_clean) - 543 AS year_ce,
       month_no, month_name_th, month_abbr_en,
       (month_no + 2) / 3 AS quarter_no,
       'Q' || ((month_no + 2) / 3) AS quarter_label,
       printf('%04d-%02d-01', (SELECT MIN(CAST(year_be AS INTEGER)) FROM export_clean) - 543, month_no) AS month_start,
       CAST(strftime('%d', date(printf('%04d-%02d-01', (SELECT MIN(CAST(year_be AS INTEGER)) FROM export_clean) - 543, month_no), '+1 month', '-1 day')) AS INTEGER) AS days_in_month
FROM tmp_month_names
ORDER BY month_no;

-- ---------------------------------------------------------------------
-- ข้อ 4: dim_product  1 แถวต่อสินค้า (พิกัด 8 หลัก + รหัสสถิติ)
--   product_key = hs8 || '-' || stat_code  เป็นคีย์เดียวที่ Power BI ใช้เชื่อมกับ fact
--   hs_chapter = เลข 2 หลักแรก, hs_heading = เลข 4 หลักแรก
--   ตรวจแล้วว่าแต่ละ (hs8, stat_code) มีชื่อไทย/อังกฤษเพียงชุดเดียว จึงใช้ MIN() ได้
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS dim_product;
CREATE TABLE dim_product AS
SELECT hs8 || '-' || stat_code AS product_key,
       hs8, stat_code,
       substr(hs8, 1, 2) AS hs_chapter,
       substr(hs8, 1, 4) AS hs_heading,
       MIN(desc_th) AS desc_th,
       MIN(desc_en) AS desc_en
FROM export_clean
GROUP BY hs8, stat_code
ORDER BY hs8, stat_code;

-- ---------------------------------------------------------------------
-- ข้อ 5: fact_export_monthly  ตารางข้อเท็จจริง (1 แถวต่อสินค้าต่อเดือน)
--   ไม่ตัดแถวมูลค่า 0 หรือค่าเล็กมากออก (ตามมาตรฐานคลีน v1.2) ให้กรองใน Power BI เมื่อจำเป็น
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS fact_export_monthly;
CREATE TABLE fact_export_monthly AS
SELECT ((CAST(year_be AS INTEGER) - 543) * 100 + CAST(month_no AS INTEGER)) AS ym_key,
       CAST(month_no AS INTEGER) AS month_no,
       hs8 || '-' || stat_code AS product_key,
       CAST(value_thb AS INTEGER) AS value_thb
FROM export_clean;

-- ---------------------------------------------------------------------
-- ข้อ 6: summary_chapter_stability  สรุปราย Chapter
--   6.1 tmp_chapter_month : มูลค่าราย Chapter x เดือน (เติม 0 ให้เดือนที่ไม่มีการส่งออก ครบ 12 เดือนทุก Chapter)
--   6.2 ค่าสถิติ: cv = ส่วนเบี่ยงเบนมาตรฐานตัวอย่าง (n-1) / ค่าเฉลี่ยรายเดือน
--       ยิ่ง cv ต่ำ ยิ่งสม่ำเสมอ ; peak_low_ratio = เดือนสูงสุด / เดือนต่ำสุด
--   6.3 stability_class เฉพาะ Chapter ที่มีสัดส่วน >= 1% ของมูลค่ารวม:
--       cv < 0.15 = คงที่ , 0.15 ถึง < 0.25 = ปานกลาง , >= 0.25 = ผันผวน
--       Chapter สัดส่วน < 1% ไม่จัดกลุ่ม เพราะมูลค่าน้อยและเปอร์เซ็นต์แกว่งง่าย
--   คำเตือน: cv ไม่ได้ตัดแนวโน้มขาขึ้นตลอดปีออก Chapter ที่โตต่อเนื่อง (เช่น เชื้อเพลิง) จึงอาจดูผันผวนขึ้น
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_chapter_month;
CREATE TABLE tmp_chapter_month AS
WITH cm AS (
  SELECT p.hs_chapter, f.month_no, SUM(f.value_thb) AS v
  FROM fact_export_monthly f JOIN dim_product p ON p.product_key = f.product_key
  GROUP BY p.hs_chapter, f.month_no
),
chapters AS (SELECT DISTINCT hs_chapter FROM dim_product)
SELECT c.hs_chapter, m.month_no, COALESCE(cm.v, 0) * 1.0 AS value_thb
FROM chapters c CROSS JOIN dim_month m
LEFT JOIN cm ON cm.hs_chapter = c.hs_chapter AND cm.month_no = m.month_no;

DROP TABLE IF EXISTS summary_chapter_stability;
CREATE TABLE summary_chapter_stability AS
WITH stat AS (
  SELECT hs_chapter,
         SUM(value_thb) AS total_thb,
         AVG(value_thb) AS avg_monthly_thb,
         sqrt(SUM((value_thb - mean_v) * (value_thb - mean_v)) / (COUNT(*) - 1)) AS sd_thb,
         MAX(value_thb) AS max_thb, MIN(value_thb) AS min_thb,
         SUM(CASE WHEN month_no BETWEEN 1 AND 3 THEN value_thb END) AS q1_thb,
         SUM(CASE WHEN month_no BETWEEN 10 AND 12 THEN value_thb END) AS q4_thb
  FROM (SELECT *, AVG(value_thb) OVER (PARTITION BY hs_chapter) AS mean_v FROM tmp_chapter_month)
  GROUP BY hs_chapter
),
pk AS (
  SELECT hs_chapter,
         MAX(CASE WHEN rn_hi = 1 THEN month_no END) AS peak_month_no,
         MAX(CASE WHEN rn_lo = 1 THEN month_no END) AS low_month_no
  FROM (SELECT hs_chapter, month_no,
               ROW_NUMBER() OVER (PARTITION BY hs_chapter ORDER BY value_thb DESC, month_no) AS rn_hi,
               ROW_NUMBER() OVER (PARTITION BY hs_chapter ORDER BY value_thb ASC,  month_no) AS rn_lo
        FROM tmp_chapter_month)
  GROUP BY hs_chapter
),
base AS (
  SELECT s.hs_chapter, s.total_thb,
         s.total_thb * 100.0 / (SELECT SUM(total_thb) FROM stat) AS share_pct,
         s.avg_monthly_thb, s.sd_thb / s.avg_monthly_thb AS cv,
         pk.peak_month_no, pk.low_month_no,
         CASE WHEN s.min_thb > 0 THEN s.max_thb / s.min_thb END AS peak_low_ratio,
         s.q1_thb, s.q4_thb,
         CASE WHEN s.q1_thb > 0 THEN (s.q4_thb - s.q1_thb) * 100.0 / s.q1_thb END AS q4_vs_q1_pct
  FROM stat s JOIN pk ON pk.hs_chapter = s.hs_chapter
)
SELECT RANK() OVER (ORDER BY b.total_thb DESC) AS rank_no,
       b.hs_chapter, c.chapter_name_en, c.chapter_name_th, c.section_no, c.section_name_th,
       CAST(ROUND(b.total_thb) AS INTEGER) AS total_thb,
       ROUND(b.share_pct, 4) AS share_pct,
       ROUND(SUM(b.share_pct) OVER (ORDER BY b.total_thb DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 4) AS cum_share_pct,
       CAST(ROUND(b.avg_monthly_thb) AS INTEGER) AS avg_monthly_thb,
       ROUND(b.cv, 4) AS cv,
       b.peak_month_no, b.low_month_no,
       ROUND(b.peak_low_ratio, 2) AS peak_low_ratio,
       CAST(ROUND(b.q1_thb) AS INTEGER) AS q1_thb,
       CAST(ROUND(b.q4_thb) AS INTEGER) AS q4_thb,
       ROUND(b.q4_vs_q1_pct, 2) AS q4_vs_q1_pct,
       CASE WHEN b.share_pct < 1 THEN 'ไม่จัดกลุ่ม (ต่ำกว่า 1%)'
            WHEN b.cv < 0.15 THEN 'คงที่'
            WHEN b.cv < 0.25 THEN 'ปานกลาง'
            ELSE 'ผันผวน' END AS stability_class
FROM base b JOIN dim_hs_chapter c ON c.hs_chapter = b.hs_chapter
ORDER BY b.total_thb DESC;

-- ---------------------------------------------------------------------
-- ข้อ 7: summary_month_total  มูลค่ารวมรายเดือนทั้งประเทศ
--   mom_pct       = % เปลี่ยนแปลงจากเดือนก่อนหน้า (เดือนแรกเป็นค่าว่าง)
--   index_vs_jan  = ดัชนีเทียบมกราคม (มกราคม = 100)
--   value_per_day_thb = มูลค่าเฉลี่ยต่อวันของเดือนนั้น (ลดอคติจากจำนวนวันไม่เท่ากัน)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS summary_month_total;
CREATE TABLE summary_month_total AS
WITH t AS (
  SELECT m.ym_key, m.month_no, m.quarter_no, m.days_in_month, SUM(f.value_thb) AS total_thb
  FROM dim_month m JOIN fact_export_monthly f ON f.ym_key = m.ym_key
  GROUP BY m.ym_key, m.month_no, m.quarter_no, m.days_in_month
)
SELECT ym_key, month_no, quarter_no, total_thb,
       ROUND((total_thb - LAG(total_thb) OVER (ORDER BY month_no)) * 100.0 / LAG(total_thb) OVER (ORDER BY month_no), 2) AS mom_pct,
       ROUND(total_thb * 100.0 / (SELECT SUM(total_thb) FROM t), 2) AS share_of_year_pct,
       ROUND(total_thb * 100.0 / FIRST_VALUE(total_thb) OVER (ORDER BY month_no), 1) AS index_vs_jan,
       CAST(ROUND(total_thb * 1.0 / days_in_month) AS INTEGER) AS value_per_day_thb
FROM t
ORDER BY month_no;

-- ---------------------------------------------------------------------
-- ข้อ 8: ตรวจสอบก่อนส่งออก (ผลควรตรงตามที่ระบุ)
--   fact_rows = 101,017 ; fact_total = 8,563,459,237,207 ; products = 11,646
--   chapters_in_summary = 96 ; fact_without_product = 0 ; months = 12
-- ---------------------------------------------------------------------
SELECT 'fact_rows' AS check_name, COUNT(*) AS result FROM fact_export_monthly
UNION ALL SELECT 'fact_total', SUM(value_thb) FROM fact_export_monthly
UNION ALL SELECT 'products', COUNT(*) FROM dim_product
UNION ALL SELECT 'chapters_in_summary', COUNT(*) FROM summary_chapter_stability
UNION ALL SELECT 'fact_without_product', COUNT(*) FROM fact_export_monthly f
  WHERE NOT EXISTS (SELECT 1 FROM dim_product p WHERE p.product_key = f.product_key)
UNION ALL SELECT 'product_without_chapter', COUNT(*) FROM dim_product p
  WHERE NOT EXISTS (SELECT 1 FROM dim_hs_chapter c WHERE c.hs_chapter = p.hs_chapter)
UNION ALL SELECT 'months', COUNT(*) FROM summary_month_total;

-- ---------------------------------------------------------------------
-- ข้อ 9: ส่งออกเป็น CSV (ทีละตาราง) ใน sqlite3 CLI:
--   .headers on
--   .mode csv
--   .output fact_export_monthly.csv
--   SELECT * FROM fact_export_monthly;
--   .output stdout
--   (ทำซ้ำกับ dim_product, dim_hs_chapter, dim_hs_section, dim_month,
--    summary_chapter_stability, summary_month_total)
--   หมายเหตุ: ไฟล์ที่ส่งมาให้ใช้ UTF-8 มี BOM และ CRLF
--
-- คำแนะนำตอนนำเข้า Power BI:
--   * ตั้งชนิดข้อมูลเป็น Text: hs8, stat_code, hs_chapter, hs_heading, product_key
--     (ถ้าปล่อยให้เดาเป็นตัวเลข เลขศูนย์นำหน้า เช่น 08 จะหาย และเชื่อมตารางไม่ติด)
--   * ความสัมพันธ์: fact[product_key] -> dim_product[product_key]
--                  dim_product[hs_chapter] -> dim_hs_chapter[hs_chapter]
--                  fact[ym_key] -> dim_month[ym_key]
--                  dim_hs_chapter[section_no] -> dim_hs_section[section_no]
-- ---------------------------------------------------------------------
