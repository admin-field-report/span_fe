"""Convert a .docx to PDF with Microsoft Word (Windows, pywin32). Used by the
mock Span API to stand in for the agent's LibreOffice render.

    python docx_to_pdf_word.py <in.docx> <out.pdf>
"""
import os
import sys

import win32com.client  # type: ignore

src, out = (os.path.abspath(p) for p in sys.argv[1:3])
word = win32com.client.DispatchEx("Word.Application")
word.Visible = False
word.DisplayAlerts = 0
try:
    doc = word.Documents.Open(src, ReadOnly=True, AddToRecentFiles=False)
    doc.SaveAs2(out, FileFormat=17)  # wdFormatPDF
    doc.Close(SaveChanges=0)
finally:
    word.Quit(SaveChanges=0)
