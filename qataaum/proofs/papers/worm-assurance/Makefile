PAPER = paper
LATEX = pdflatex
BIBTEX = bibtex

.PHONY: all clean watch

all: $(PAPER).pdf

$(PAPER).pdf: $(PAPER).tex $(PAPER).bib
	$(LATEX) $(PAPER)
	$(BIBTEX) $(PAPER)
	$(LATEX) $(PAPER)
	$(LATEX) $(PAPER)

# Requires latexmk: tlmgr install latexmk
watch:
	latexmk -pdf -pvc $(PAPER)

clean:
	rm -f *.aux *.bbl *.blg *.log *.out *.toc *.fls *.fdb_latexmk *.synctex.gz

distclean: clean
	rm -f $(PAPER).pdf
