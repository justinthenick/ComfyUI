<#
.SYNOPSIS
    Verify .gitignore effectiveness and show untracked/ignored files.

.DESCRIPTION
    Runs through:
      - untracked files
      - ignored files (matching .gitignore)
      - files staged for commit
    Helps confirm your .gitignore is airtight before committing.
#>

Write-Host "=== Git Status Summary ===" -ForegroundColor Cyan
git status --short

Write-Host "`n=== Ignored Files (per .gitignore) ===" -ForegroundColor Yellow
git status --ignored --short | Where-Object { $_ -like "!!*" }

Write-Host "`n=== Untracked Files (not ignored) ===" -ForegroundColor Red
git status --short | Where-Object { $_ -like "??*" }

Write-Host "`n=== Staged Changes (ready to commit) ===" -ForegroundColor Green
git diff --cached --name-status
Write-Host "`n=== End of Git Status Check ===" -ForegroundColor Cyan
# End of Check-GitClean.ps1
# -------------------------
# .gitignore
# -------------------------
# See https://help.github.com/articles/ignoring-files/ for more about ignoring files.
# See https://git-scm.com/docs/gitignore for details about the format.
# See https://www.gitignore.io/ for generating .gitignore files for specific environments.
# See https://www.toptal.com/developers/gitignore for an online .gitignore generator.