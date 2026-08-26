"""Arabic normalization for indexing only.

C6: nothing here ever reaches the user. `text_uthmani` is the display and diff
stream; the output of this module populates `text_norm`, which is an index key.

Every rule below records what it merges and what it risks merging. A rule that
erases a distinction a memoriser needs is a bug, not a tuning choice (brief §4).
"""
from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, replace

# --- character classes -------------------------------------------------------

# Phonetic diacritics. Merging these collapses e.g. a genitive/accusative
# contrast on an otherwise identical word, which is exactly the class of
# mutashabih the product exists to teach. Stripped at `standard` and above,
# never at `strict`.
HARAKAT = "".join(
    [
        "\u064B",  # tanwin fath
        "\u064C",  # tanwin damm
        "\u064D",  # tanwin kasr
        "\u064E",  # fatha
        "\u064F",  # damma
        "\u0650",  # kasra
        "\u0651",  # shadda
        "\u0652",  # sukun
        # Qur'anic vowel variants. Different prints spell the same vowel with
        # different codepoints: the QPC Hafs ayah-level export writes tanwin
        # damm as U+0657 where the word-by-word Uthmani export uses U+064C.
        # Treating them apart would split one word into two index keys.
        # U+0654/U+0655 (hamza above/below) are deliberately NOT here: they
        # form letters rather than vowels, and folding them would merge hamza
        # carriers even at `strict`.
        "\u0657",  # inverted damma
        "\u0658",  # mark noon ghunna
        "\u0659",  # zwarakay
        "\u065a",  # vowel sign small v above
        "\u065b",  # vowel sign inverted small v above
        "\u065c",  # vowel sign dot below
        "\u065d",  # reversed damma
        "\u065e",  # fatha with two dots
        "\u065f",  # wavy hamza below
    ]
)

# Qur'anic annotation: waqf signs, sajda marks, rub' marks, end-of-ayah.
# These are reciter's instructions, not letters. Removing them merges nothing
# lexical, so it is safe even at `strict`.
ANNOTATION = (
    "\u0610-\u061A"  # Arabic signs (salla, alayhi wa sallam, ...)
    "\u06D6-\u06DC"  # small high marks: waqf, sajdah, seen, ...
    "\u06DD"  # end of ayah
    "\u06DE"  # start of rub' el hizb
    "\u06DF-\u06E4"  # small high marks: rounded zero, meem, madda, ...
    "\u06E7\u06E8"  # small high yeh, small high noon
    "\u06E9"  # place of sajdah
    "\u06EA-\u06ED"  # small low marks
    "\u08F0-\u08F3"  # open tanwin variants
)

# Superscript alif and the small wāw/yā'. These carry real reading information
# (ٰ marks a long vowel that is not written as a letter), so they survive
# `strict`. At `standard` they are dropped because their presence or absence is
# an orthographic convention across prints rather than a wording difference.
SUPERSCRIPT = (
    "\u0670"  # superscript alef
    "\u06E5"  # small waw
    "\u06E6"  # small yeh
    "\u0656"  # subscript alef, the low counterpart of U+0670
    # Maddah. U+0627+U+0653 composes to \u0622, but U+0623+U+0653 has no precomposed
    # form, so the ayah-level export leaves a bare maddah where the word-by-word
    # export spells the same word with a seat hamza. `unify_alif` already merges
    # \u0622/\u0623/\u0625, so the mark carries no distinction by the time we reach it.
    "\u0653"
)

# Zero-width joiners and the tatweel elongation. Purely presentational.
INVISIBLE = "\u200B-\u200F\u2060\uFEFF"
TATWEEL = "\u0640"

_RE_HARAKAT = re.compile(f"[{HARAKAT}]")
_RE_ANNOTATION = re.compile(f"[{ANNOTATION}]")
_RE_SUPERSCRIPT = re.compile(f"[{SUPERSCRIPT}]")
_RE_INVISIBLE = re.compile(f"[{INVISIBLE}{TATWEEL}]")
_RE_SPACE = re.compile(r"\s+")
# Hamza above/below left stranded once their seat letter is stripped.
_RE_ORPHAN_HAMZA = re.compile("[ٕٔ]")
# Arabic-Indic digits: QUL stores one ayah-number token per ayah in `words`.
_RE_DIGIT = re.compile(r"[\u0660-\u0669\u06F0-\u06F9]")


@dataclass(frozen=True)
class Profile:
    """Each step is individually toggleable so a rule can be tested alone."""

    strip_annotation: bool = True
    strip_invisible: bool = True
    strip_harakat: bool = False
    strip_superscript: bool = False
    drop_orphan_hamza: bool = False
    unify_alif: bool = False
    unify_teh_marbuta: bool = False
    unify_alif_maqsura: bool = False
    unify_hamza_carriers: bool = False
    drop_internal_space: bool = False


# `strict` keeps every phonetic distinction. Used in §6 to catch pairs whose
# only difference is a ḥaraka or a case ending — the pairs `standard` merges.
STRICT = Profile()

# `standard` is the detection profile. It merges orthographic variation across
# prints while preserving consonantal skeleton and word identity.
STANDARD = replace(
    STRICT,
    strip_harakat=True,
    strip_superscript=True,
    drop_orphan_hamza=True,
    unify_alif=True,
    unify_teh_marbuta=True,
    unify_alif_maqsura=True,
    drop_internal_space=True,
)

# `aggressive` additionally folds hamza carriers. This merges ؤ/ئ/ء, which can
# erase a genuine spelling contrast, so it is never the detection default.
AGGRESSIVE = replace(STANDARD, unify_hamza_carriers=True)

PROFILES = {"strict": STRICT, "standard": STANDARD, "aggressive": AGGRESSIVE}


def normalize(token: str, profile: Profile | str = STANDARD) -> str:
    """Return the index key for `token`. Never use the result for display."""
    if isinstance(profile, str):
        try:
            profile = PROFILES[profile]
        except KeyError:
            raise ValueError(
                f"unknown profile {profile!r}; expected one of {sorted(PROFILES)}"
            ) from None

    # NFC first so that decomposed input from any source compares equal.
    out = unicodedata.normalize("NFC", token)

    if profile.strip_annotation:
        out = _RE_ANNOTATION.sub("", out)
    if profile.strip_invisible:
        out = _RE_INVISIBLE.sub("", out)
    if profile.strip_harakat:
        out = _RE_HARAKAT.sub("", out)
    if profile.strip_superscript:
        out = _RE_SUPERSCRIPT.sub("", out)

    # Recompose. The Uthmani word-by-word export spells the madda alif as
    # tatweel + U+0654 + fatha + alef; once the tatweel and harakat are gone the
    # hamza sits next to a base it can combine with, so a second NFC pass turns
    # it back into a single letter instead of leaving a stray combining mark.
    out = unicodedata.normalize("NFC", out)

    if profile.drop_orphan_hamza:
        # Anything still uncomposed after that pass has no base letter of its
        # own — it is a seat-only hamza from the Uthmani orthography. Dropping
        # it merges the spellings of آ/أ/إ, which `unify_alif` merges anyway.
        # Genuine ؤ/ئ are unaffected: NFC has already composed them.
        out = _RE_ORPHAN_HAMZA.sub("", out)

    if profile.unify_alif:
        # أ إ آ ٱ → ا. Merges hamzat al-wasl/qat' spelling, which varies by
        # print. Risk: loses the أ/إ contrast, which is not a wording contrast.
        out = re.sub("[\u0622\u0623\u0625\u0671\u0672\u0673\u0675]", "\u0627", out)
    if profile.unify_teh_marbuta:
        # ة → ه. Merges the two ways a final -a(t) is written. Risk: merges a
        # genuine final هـ with ة; rare and always recoverable from Uthmani.
        out = out.replace("\u0629", "\u0647")
    if profile.unify_alif_maqsura:
        # ى → ي. Merges final alif maqsura with yā'. Risk: merges a real final
        # yā' with alif maqsura; the Uthmani stream keeps them apart.
        out = out.replace("\u0649", "\u064A")
    if profile.unify_hamza_carriers:
        # ؤ ئ → ء. Aggressive only: drops the carrier letter entirely.
        out = re.sub("[\u0624\u0626]", "\u0621", out)

    out = _RE_SPACE.sub(" ", out).strip()
    if profile.drop_internal_space:
        # A words row holds exactly one token, but the Uthmani rasm writes a
        # couple of words with a space inside them. Keeping that space would put
        # a space in an index key, so the key drops it; `text_uthmani` still
        # carries the spacing byte-for-byte (C6).
        out = out.replace(" ", "")
    return out


def is_ayah_marker(token: str) -> bool:
    """True for QUL's per-ayah number token (e.g. ٢٥٥), which is not a word."""
    return bool(_RE_DIGIT.search(token))
