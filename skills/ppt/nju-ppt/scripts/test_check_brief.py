"""Regression checks for concise subtitles without a mandatory four-plus-four form."""
from pathlib import Path

from check_brief import Brief, MAX_CHAPTER_SUBTITLE


def main():
    examples = Path(__file__).resolve().parents[1] / "references/examples"
    good = (examples / "brief-ok.md").read_text(encoding="utf-8")
    original = "长路漫漫，上下求索"
    assert original in good
    for subtitle in ("明确研究问题", "以证据判断适用范围", "—", original):
        brief = Brief("test", good.replace(original, subtitle))
        brief.check()
        assert not brief.issues, (subtitle, brief.issues)
    brief = Brief("test", good.replace(original, "长" * (MAX_CHAPTER_SUBTITLE + 1)))
    brief.check()
    assert any("副题" in issue and "超过" in issue for issue in brief.issues)
    invalid = Brief("test", (examples / "brief-bad.md").read_text(encoding="utf-8"))
    invalid.check()
    assert invalid.issues
    print("PASS: concise subtitles, optional subtitle, legacy subtitle, length bound, invalid fixture")


if __name__ == "__main__":
    main()
