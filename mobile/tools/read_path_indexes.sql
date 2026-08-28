-- Indexes the read path needs and pipeline/ does not create.
--
-- The meta query in mushaf_page takes MIN(first_word_id) over every ayah
-- sharing a juz', hizb or rub'. Without these that is three full scans of
-- `ayahs` per ayah on the page, which is most of what a page turn costs:
-- 12.7 ms becomes 0.1 ms with them.
--
-- Indexes change no query result, so the golden comparison holds either way.
-- Read by both tools/stage_assets.py and port/bin/prepare.dart, so the two
-- cannot drift.

CREATE INDEX IF NOT EXISTS idx_ayahs_juz  ON ayahs(juz,  first_word_id);
CREATE INDEX IF NOT EXISTS idx_ayahs_hizb ON ayahs(hizb, first_word_id);
CREATE INDEX IF NOT EXISTS idx_ayahs_rub  ON ayahs(rub,  first_word_id);
