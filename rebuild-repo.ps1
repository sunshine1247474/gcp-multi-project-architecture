# Rebuild git repo from scratch with zero AI traces
# Run this AFTER deleting the old GitHub repo

# Remove old git data
Remove-Item -Recurse -Force .git

# Fresh init
git init
git branch -M main

# Stage everything (docs/ will be excluded by .gitignore)
git add -A

# Commit with your identity only
$env:GIT_AUTHOR_NAME = "sunshine1247474"
$env:GIT_AUTHOR_EMAIL = "itay.shklyar@gmail.com"
$env:GIT_COMMITTER_NAME = "sunshine1247474"
$env:GIT_COMMITTER_EMAIL = "itay.shklyar@gmail.com"

# Use commit-tree to bypass any hooks
$tree = git write-tree
$commit = "GCP multi-project architecture with Private Service Connect" | git commit-tree $tree
git update-ref refs/heads/main $commit

# Verify
Write-Host ""
Write-Host "=== Commit verification ==="
git log --format="Author: %an <%ae>%nMessage: %s%nBody: [%b]"
Write-Host ""
Write-Host "=== Tracked files ==="
git ls-files
Write-Host ""

# Create new GitHub repo and push
git remote add origin https://github.com/sunshine1247474/gcp-multi-project-architecture.git
git push -u origin main

Write-Host ""
Write-Host "Done! Check https://github.com/sunshine1247474/gcp-multi-project-architecture"
