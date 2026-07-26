Set-Location $PSScriptRoot

Write-Host "Building paper.pdf..." -ForegroundColor Cyan

pdflatex -interaction=nonstopmode paper.tex
bibtex paper
pdflatex -interaction=nonstopmode paper.tex
pdflatex -interaction=nonstopmode paper.tex

if (Test-Path paper.pdf) {
    Write-Host "Done: $PSScriptRoot\paper.pdf" -ForegroundColor Green
    Start-Process paper.pdf
} else {
    Write-Host "Build failed - check paper.log" -ForegroundColor Red
}
