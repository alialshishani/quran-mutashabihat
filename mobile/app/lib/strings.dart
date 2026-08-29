// What the app says, and the numerals it says it in.
//
// The chrome used to speak English, in the project's own private vocabulary:
// Forks, Roads, Pegs, Stops, Danger, `all_but_one`. That metaphor is a good
// one and it stays -- in the source, where it was written for. On screen it
// asked a hafiz to learn the author's model of his own recitation before he
// could use the app, and it named in English three things Arabic already has
// exact words for: al-mutashabihat, al-lafz al-mushtarak, al-dabit.
//
// So the chrome speaks Arabic, and every identifier in the code is untouched.
// This file is the only place the two meet.
//
// Numerals are Arabic-Indic throughout. The ayah markers on the page are set
// in them by the mushaf's own font; a page number underneath in 1-2-3 is the
// app talking over the book.

// ----------------------------------------------------------------- numerals

const List<String> _digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

/// An integer in Arabic-Indic numerals.
String ar(int n) {
  if (n < 0) return '-${ar(-n)}';
  final b = StringBuffer();
  for (final unit in n.toString().codeUnits) {
    b.write(_digits[unit - 0x30]);
  }
  return b.toString();
}

/// Every ASCII digit in a string, in Arabic-Indic numerals. For the strings
/// that arrive already formed -- verse keys like `2:255` above all.
String arDigits(String s) {
  final b = StringBuffer();
  for (final unit in s.codeUnits) {
    b.write(unit >= 0x30 && unit <= 0x39
        ? _digits[unit - 0x30]
        : String.fromCharCode(unit));
  }
  return b.toString();
}

/// A counted noun, in the four shapes Arabic actually counts in.
///
/// Not decoration: "٢ مواضع" and "١١ مواضع" are both wrong, and a memorisation
/// app that cannot count in Arabic has said something about how much of it was
/// thought through.
///
/// [one] and [two] carry their own number; [few] is the plural taken by 3-10,
/// and [many] the singular accusative taken by 11 and up.
String arCount(int n, String one, String two, String few, String many) {
  if (n == 1) return one;
  if (n == 2) return two;
  if (n >= 3 && n <= 10) return '${ar(n)} $few';
  return '${ar(n)} $many';
}

String places(int n) => arCount(n, 'موضع واحد', 'موضعان', 'مواضع', 'موضعًا');
String ways(int n) => arCount(n, 'وجه واحد', 'وجهان', 'أوجه', 'وجهًا');
String surahsN(int n) => arCount(n, 'سورة واحدة', 'سورتان', 'سور', 'سورةً');
String wordsN(int n) => arCount(n, 'كلمة واحدة', 'كلمتان', 'كلمات', 'كلمةً');
String ayatN(int n) => arCount(n, 'آية واحدة', 'آيتان', 'آيات', 'آيةً');
String phrasesN(int n) => arCount(n, 'لفظ واحد', 'لفظان', 'ألفاظ', 'لفظًا');
String timesN(int n) => arCount(n, 'مرة واحدة', 'مرتان', 'مرات', 'مرةً');
String daysN(int n) => arCount(n, 'يوم واحد', 'يومان', 'أيام', 'يومًا');
String repeatsN(int n) =>
    arCount(n, 'تكرار واحد', 'تكراران', 'تكرارات', 'تكرارًا');

String pageN(int n) => 'صفحة ${ar(n)}';
String juzN(int n) => 'الجزء ${ar(n)}';

// ------------------------------------------------------------ the app, the bar

const String kAppName = 'المصحف';

const String kNavToday = 'اليوم';
const String kNavMushaf = 'المصحف';
const String kNavRecall = 'التسميع';
const String kNavForks = 'المتشابهات';
const String kNavDrill = 'التمرين';

// ----------------------------------------------------------------- the drawer

const String kMenu = 'القائمة';
const String kIndexAndSearch = 'الفهرس والبحث';
const String kIndexGloss = 'السور، الأجزاء، ما علَّمتَه، وما تعثَّرتَ فيه';
const String kSectionRecall = 'التسميع';
const String kStopAtForks = 'التوقف عند مواضع الافتراق';
const String kStopAtForksGloss =
    'أمسِك الكلمة التي يفترق عندها اللفظ المشترك، بدل ستر الآية كاملة.';
const String kSectionLight = 'الإضاءة';
const String kLightDay = 'نهار';
const String kLightNight = 'ليل';
const String kLightAuto = 'تلقائي';

// ------------------------------------------------------------------ the sheet

const String kBookmarkAdd = 'ضع علامة على هذه الآية';
const String kBookmarkRemove = 'ارفع العلامة';
const String kShowAll = 'أظهر الكل';
const String kCoverAgain = 'استر من جديد';
String kGivenOf(int given, int all) => '${ar(given)} من ${ar(all)}';
const String kMissedTally = 'تعثُّر';
String kMarkedMissed(String key) => 'سُجِّل التعثر في ${arDigits(key)}';
const String kCoachReveal = 'المس الصفحة ليظهر ما بعدها، وأطِل المس إن تعثَّرت';
const String kCoachChrome = 'المس الصفحة لإظهار الشريط';
const String kGotIt = 'فهمت';

// ------------------------------------------------------------------ the index

const String kSearchHint = 'ابحث في النص';
const String kTabSurahs = 'السور';
const String kTabJuz = 'الأجزاء';
const String kTabMarked = 'العلامات';
const String kTabMissed = 'المتعثرة';
const String kGo = 'انتقل';
String kPageField(int pages) => 'صفحة ١ – ${ar(pages)}';
const String kNothingFound =
    'لا نتيجة. البحث يجري على الرسم الإملائي — الذي تكتبه — لا على الرسم '
    'العثماني المطبوع في الصفحة.';
const String kNothingMissed =
    'لا تعثُّر بعد. في التسميع، أطِل المس على الصفحة إذا لم تأتِك الآية، '
    'فتُحفظ هنا.';
const String kNothingMarked =
    'لا علامة بعد. أظهِر شريط الصفحة، واختر آية، ثم ضع عليها علامة.';
const String kLearnt = 'حفظتُها';
const String kMakki = 'مكية';
const String kMadani = 'مدنية';

// ------------------------------------------------------------------ the forks

const String kAll = 'الكل';
const String kSortUseful = 'الأنفع';
const String kSortPositions = 'عدد المواضع';
const String kSortBranches = 'عدد الأوجه';
const String kSortSurahs = 'عدد السور';
const String kPrevious = 'السابق';
const String kNext = 'التالي';
const String kEndsSurah = 'تنتهي السورة هنا';

// ------------------------------------------------------------------ the drill

const String kQuestion = 'كيف يُكمل هذا الموضع؟';
const String kLeadInBefore = 'آخر الآية التي قبلها';
const String kPegStrength = 'قوة الضابط';
const String kNoPeg =
    'لا ضابط محقَّق لهذا الموضع — لا تُخرِج مجموعةُ الاشتباه علامةً تفصله وحدها.';
String kSeeOnPage(int p) => 'انظرها في ${pageN(p)}';
String kOneOf(int n) => 'أحد ${places(n)}';
String kOrdinalHere(int i, int n) => 'الـ${ar(i)} من ${ar(n)} في السورة';

// ------------------------------------------------------------------ the today

const String kResume = 'تابع القراءة';
const String kStartDrill = 'ابدأ التمرين';
const String kNothingDue = 'لا مستحق اليوم';
const String kNothingDueGloss =
    'راجعتَ كل ما حلَّ وقته. عُد غدًا، أو مرِّن على ما شئت.';
const String kDrillAnyway = 'مرِّن على أي حال';
const String kSectionContinue = 'حيث وقفت';
const String kSectionNeedsWork = 'ما تحتاج إليه';
const String kSectionMastery = 'التمكُّن';
const String kMastered = 'راسخ';
const String kLearning = 'قيد الترسيخ';
const String kUnseen = 'لم يبدأ';
String kDueNow(int n) => '${places(n)} حلَّ وقتها';
String kStreak(int n) => n == 0 ? 'ابدأ اليوم' : '${daysN(n)} متتابعة';
const String kNoPoolTitle = 'لا تمرين بعد';
const String kNoPoolGloss =
    'لم تُبنَ جداول المتشابهات في هذه النسخة، فلا مواضع تُسأل عنها.';

// ---------------------------------------------------------------- the session

const String kSessionDone = 'انتهت الجلسة';
String kSessionScore(int right, int all) => '${ar(right)} من ${ar(all)}';
const String kSessionAgain = 'أعد المتعثرة';
const String kSessionFinish = 'إنهاء';
const String kSessionPerfect = 'تمَّت الجلسة بلا خطأ.';
String kSessionShaky(int n) => 'عادت ${places(n)} إلى أول الصندوق.';

// ------------------------------------------------------------------ the panel

const String kNoOfficial = 'لا متشابه معتمد في هذه الآية';
String kOfficialCount(int n) => '${phrasesN(n)} من المعتمد';
const String kNothingHere =
    'لا تحمل هذه الآية لفظًا من القائمة المعتمدة، ولم يُكشف فيها تكرار.';
const String kNothingCurated =
    'لا لفظ من القائمة المعتمدة. وما كُشف مذكور أدناه.';
String kMorePhrases(int n) => '${phrasesN(n)} أخرى هنا';
const String kMorePhrasesGloss =
    'بقية اللفظ المشترك الذي تحمله هذه الآية، مرتَّبًا بحسب بُعده عن نظائره';
String kDetectedCount(int n) => '${repeatsN(n)} مكشوفة';
const String kDetectedGloss = 'كشفُ المشروع نفسه، لا القائمة المعتمدة';
String kOtherPlaces(int n) => '${places(n)} الأخرى';
const String kHere = 'هنا';
const String kElsewhere = 'وفي غيرها';
String kGoesAgainst(int n) => 'هذا الموضع يخالف ${places(n)}';
String kShareRoad(int n) => '${places(n)} تشترك في هذا اللفظ';
String kOtherWays(int n, int p) =>
    '${ways(n)} أخرى، ${p == n ? "في كل منها موضع" : places(p)}';
const String kCrossesSurah = 'يعبر السور';
const String kNoPegShort = 'لا ضابط محقَّق لهذا الموضع';

// ----------------------------------------------------------------- the states

const String kLoading = 'يُفتح المصحف…';
const String kLoadFailedTitle = 'تعذَّر فتح المصحف';
const String kLoadFailedGloss =
    'لم يُفتح مخزن النص. أعِد تشغيل التطبيق؛ فإن عاد الخطأ فالنسخة المثبتة ناقصة.';
