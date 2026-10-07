"""Synchronize the approved SF-0201-009 icon paragraph into the publication copy.

This deliberately changes one paragraph, retaining the DOCX structure and
formatting. The Markdown specification remains the searchable contract.
"""

from pathlib import Path

from docx import Document


ROOT = Path(__file__).resolve().parent.parent
MARKDOWN = ROOT / "docs/SiteForge-Specification.md"
PUBLICATION = ROOT / "docs/SiteForge-Specification.docx"


def main() -> None:
    lines = MARKDOWN.read_text(encoding="utf-8").splitlines()
    heading = "##### SF-0201-009 — Application identity and adaptive chrome"
    index = lines.index(heading)
    requirement = next(line for line in lines[index + 1 :] if line.startswith("Requirement  "))
    acceptance = next(line for line in lines[index + 1 :] if line.startswith("Acceptance criteria  "))

    document = Document(PUBLICATION)
    matches = [i for i, paragraph in enumerate(document.paragraphs)
               if paragraph.text.strip() == heading.removeprefix("##### ")]
    if len(matches) != 1:
        raise ValueError("Expected exactly one SF-0201-009 publication heading")
    for offset, prefix, text in (
        (1, "Requirement  ", requirement),
        (3, "Acceptance criteria  ", acceptance),
    ):
        paragraph = document.paragraphs[matches[0] + offset]
        if not paragraph.text.startswith(prefix) or len(paragraph.runs) != 1:
            raise ValueError("Unexpected SF-0201-009 publication paragraph structure")
        paragraph.runs[0].text = text
    document.save(PUBLICATION)


if __name__ == "__main__":
    main()
