#!/usr/bin/env python3
"""Validate an nju-ppt brief.md against the fixed style contract.

Usage:  python check_brief.py brief.md
Exit:   0 pass, 1 violations, 2 unreadable/unparseable.
Stdlib only; runs on Python 3.8+.
"""
import re
import sys
from typing import Dict, List, Optional, Tuple

PROTOTYPES = {
    "cover", "toc", "chapter", "pillars4", "two_col", "timeline",
    "points3", "chart_column", "chart_combo", "table", "ending",
}
TITLED = {
    "pillars4", "two_col", "timeline", "points3",
    "chart_column", "chart_combo", "table",
}
CHARTED = {"chart_column", "chart_combo", "table"}

MIN_PAGES, MAX_PAGES = 6, 18
MIN_CHAPTERS, MAX_CHAPTERS = 3, 5
MAX_CHAPTER_NAME = 6
MAX_CHAPTER_SUBTITLE = 30
MAX_BULLETS = 3
MAX_BULLET_CHARS = 18
MAX_BODY_CHARS = 120

BANNED = ["赋能", "抓手", "闭环", "生态", "显著提升", "全面提升",
          "深度融合", "助力", "打造", "护航"]
TEMPLATE_WORDS = ["单击此处", "输入文字", "请在这里添加", "为了最终演示",
                  "请尽量言简意赅"]

META_KEYS = ("场景", "听众", "时长", "页数", "主张")


def measure(text: str) -> int:
    """Count CJK chars as 1 and each ASCII word/digit-run as 1."""
    text = re.sub(r"\s+", "", text)
    ascii_runs = len(re.findall(r"[A-Za-z0-9]+", text))
    cjk = len(re.findall(r"[\u4e00-\u9fff]", text))
    other = len(re.sub(r"[A-Za-z0-9\u4e00-\u9fff]", "", text))
    return ascii_runs + cjk + other


def split_row(line: str) -> List[str]:
    s = line.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|"):
        s = s[:-1]
    return [c.strip() for c in s.split("|")]


def is_separator(cells: List[str]) -> bool:
    return bool(cells) and all(re.fullmatch(r":?-{2,}:?", c) for c in cells)


class Brief(object):
    def __init__(self, path: str, text: str):
        self.path = path
        self.lines = text.splitlines()
        self.meta = {}          # type: Dict[str, str]
        self.chapters = []      # type: List[Tuple[int, List[str]]]
        self.pages = []         # type: List[Tuple[int, List[str]]]
        self.data = []          # type: List[Tuple[int, List[str]]]
        self.cuts = []          # type: List[str]
        self.issues = []        # type: List[str]
        self._parse()

    def _parse(self):
        section = None
        for idx, raw in enumerate(self.lines, 1):
            line = raw.strip()
            if line.startswith("## "):
                section = line[3:].strip()
                continue
            if section is None:
                m = re.match(r"^[-*]\s*([^:：]+)\s*[:：]\s*(.*)$", line)
                if m and m.group(1).strip() in META_KEYS:
                    self.meta[m.group(1).strip()] = m.group(2).strip()
                continue
            if not line:
                continue
            if section.startswith("章节") and line.startswith("|"):
                cells = split_row(line)
                if not is_separator(cells) and not cells[0].startswith("章节"):
                    self.chapters.append((idx, cells))
            elif section.startswith("页面") and line.startswith("|"):
                cells = split_row(line)
                if not is_separator(cells) and not cells[0].startswith("页"):
                    self.pages.append((idx, cells))
            elif section.startswith("数据") and line.startswith("|"):
                cells = split_row(line)
                if not is_separator(cells) and not cells[0].startswith("数值"):
                    self.data.append((idx, cells))
            elif section.startswith("删减") and re.match(r"^[-*]\s+", line):
                self.cuts.append(re.sub(r"^[-*]\s+", "", line))

    def bad(self, line: Optional[int], msg: str):
        where = "line %d: " % line if line else ""
        self.issues.append(where + msg)

    def check(self):
        for key in ("场景", "听众", "页数", "主张"):
            if not self.meta.get(key):
                self.bad(None, "缺少元信息：%s" % key)

        declared = self.meta.get("页数", "")
        if declared and not declared.isdigit():
            self.bad(None, "页数必须是数字，当前是 %r" % declared)
        elif declared:
            n = int(declared)
            if not (MIN_PAGES <= n <= MAX_PAGES):
                self.bad(None, "页数 %d 超出 %d–%d" % (n, MIN_PAGES, MAX_PAGES))
            if n != len(self.pages):
                self.bad(None, "声明 %d 页，页面表实际 %d 行" % (n, len(self.pages)))

        self._check_chapters()
        self._check_pages()
        self._check_data()
        self._check_text_rules()

        if len(self.cuts) < 2:
            self.bad(None, "「删减」至少 2 条，当前 %d 条" % len(self.cuts))

    def _check_chapters(self):
        if not (MIN_CHAPTERS <= len(self.chapters) <= MAX_CHAPTERS):
            self.bad(None, "章节数 %d，应在 %d–%d" % (
                len(self.chapters), MIN_CHAPTERS, MAX_CHAPTERS))
        for line, cells in self.chapters:
            if len(cells) < 3:
                self.bad(line, "章节行需要 3 列：章节 | 副题 | 结论")
                continue
            name, sub, conclusion = cells[0], cells[1], cells[2]
            if not name:
                self.bad(line, "章节名为空")
            elif measure(name) > MAX_CHAPTER_NAME:
                self.bad(line, "章节名「%s」%d 字，超过 %d" % (
                    name, measure(name), MAX_CHAPTER_NAME))
            if not conclusion:
                self.bad(line, "章节「%s」缺结论" % name)
            if sub and sub not in ("—", "-"):
                if measure(sub) > MAX_CHAPTER_SUBTITLE:
                    self.bad(line, "副题「%s」超过 %d 字" % (sub, MAX_CHAPTER_SUBTITLE))

    def _check_pages(self):
        seen = []
        for line, cells in self.pages:
            if len(cells) < 5:
                self.bad(line, "页面行需要 5 列：页 | 原型 | 标题 | 要点 | 图表")
                continue
            page_no, proto, title, points, chart = cells[:5]
            if not page_no.isdigit():
                self.bad(line, "页码不是数字：%r" % page_no)
            else:
                seen.append(int(page_no))
            if proto not in PROTOTYPES:
                self.bad(line, "原型「%s」不在白名单（见 style-contract 第 5 节）" % proto)
                continue
            if title in ("", "—", "-"):
                self.bad(line, "第 %s 页缺标题" % page_no)
            elif proto in TITLED:
                n = measure(title)
                if not (6 <= n <= 12):
                    self.bad(line, "标题「%s」%d 字，应 6–12 字" % (title, n))
            if points not in ("", "—", "-"):
                items = [p.strip() for p in re.split(r"[；;]", points) if p.strip()]
                if len(items) > MAX_BULLETS:
                    self.bad(line, "第 %s 页要点 %d 条，上限 %d" % (
                        page_no, len(items), MAX_BULLETS))
                for item in items:
                    if measure(item) > MAX_BULLET_CHARS:
                        self.bad(line, "要点「%s」%d 字，超过 %d" % (
                            item, measure(item), MAX_BULLET_CHARS))
                total = sum(measure(i) for i in items)
                if total > MAX_BODY_CHARS:
                    self.bad(line, "第 %s 页正文合计 %d 字，超过 %d" % (
                        page_no, total, MAX_BODY_CHARS))
            if chart not in ("", "—", "-"):
                if chart not in ("column", "combo", "table"):
                    self.bad(line, "图表「%s」只能是 column / combo / table / —" % chart)
                if chart == "column" and proto != "chart_column":
                    self.bad(line, "图表 column 必须配原型 chart_column")
                if chart == "combo" and proto != "chart_combo":
                    self.bad(line, "图表 combo 必须配原型 chart_combo")
                if chart == "table" and proto != "table":
                    self.bad(line, "图表 table 必须配原型 table")
        if seen and seen != list(range(1, len(seen) + 1)):
            self.bad(None, "页码必须从 1 连续到 %d，当前 %s" % (len(seen), seen))

    def _check_data(self):
        needs = any((cells[4] if len(cells) > 4 else "") in ("column", "combo", "table")
                    for _, cells in self.pages)
        if needs and not self.data:
            self.bad(None, "有图表/表格页，但「数据」表为空")
        for line, cells in self.data:
            if len(cells) < 4:
                self.bad(line, "数据行需要 4 列：数值 | 单位 | 口径 | 来源")
                continue
            for i, name in enumerate(("数值", "单位", "口径", "来源")):
                if not cells[i] or cells[i] in ("—", "-"):
                    self.bad(line, "数据行「%s」列为空" % name)

    def _check_text_rules(self):
        for idx, raw in enumerate(self.lines, 1):
            for w in BANNED:
                if w in raw:
                    self.bad(idx, "禁词「%s」" % w)
            for w in TEMPLATE_WORDS:
                if w in raw:
                    self.bad(idx, "残留模板话「%s」" % w)


def main(argv: List[str]) -> int:
    if len(argv) != 2:
        print("usage: check_brief.py <brief.md>")
        return 2
    path = argv[1]
    try:
        with open(path, encoding="utf-8-sig") as f:
            text = f.read()
    except OSError as exc:
        print("cannot read %s: %s" % (path, exc))
        return 2
    brief = Brief(path, text)
    if not brief.pages and not brief.chapters:
        print("cannot parse: 没找到「## 章节」或「## 页面」表")
        return 2
    brief.check()
    if brief.issues:
        for issue in brief.issues:
            print("FAIL " + issue)
        print("---")
        print("%d issue(s)" % len(brief.issues))
        return 1
    print("PASS %d pages, %d chapters, %d data rows" % (
        len(brief.pages), len(brief.chapters), len(brief.data)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
