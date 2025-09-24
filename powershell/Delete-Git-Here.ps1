# This script will delete git in current folder and child folders
Get-ChildItem -Path . -Include .git -Recurse -Directory -Force | ForEach-Object { Remove-Item $_.FullName -Recurse -Force }
Get-ChildItem -Path . -Include .gitattributes -Recurse -File -Force | Remove-Item -Force
Get-ChildItem -Path . -Include .gitignore -Recurse -File -Force | Remove-Item -Force
