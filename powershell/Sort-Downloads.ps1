<# 
.SYNOPSIS
  Automatically organize your Downloads folder into categorized review buckets and final destinations.

.DESCRIPTION
  This script helps you tame download chaos by automatically sorting files into organized folders:
  
  WHAT IT CREATES IN YOUR DOWNLOADS FOLDER:
  - !PDFs\ToSort - All PDF files go here for review
  - !Installers_Quarantine - Software installers (for security review before running)
  - !Pictures_Review - Images that need sorting
  - !_TBD - "To Be Determined" - everything else that doesn't fit other categories
  - !Archives_Review - ZIP files, RAR files, etc.
  - _SortLogs - CSV logs of what was moved where
  
  WHAT IT MOVES TO YOUR MOVIES FOLDER:
  - Movie files (.mp4, .mkv, etc.) 
  - Folders containing movie files (it searches inside folders)
  
  SAFETY FEATURES:
  - Uses -WhatIf to preview changes without actually moving anything
  - Creates timestamped backups if files already exist at destination
  - Logs everything to CSV for tracking
  - Only processes top-level items (won't mess with your organized subfolders)

.PARAMETER Downloads
  The path to your Downloads folder. Defaults to D:\Users\felix\Downloads
  Change this to match your actual Downloads path.

.PARAMETER Movies
  Where to move movie files. Defaults to I:\Movies
  Change this to your preferred movies folder.

.EXAMPLE
  # SAFE WAY: Preview what will happen without actually moving anything
  pwsh -File .\Sort-Downloads.ps1 -WhatIf -Verbose

.EXAMPLE
  # Actually run the sorting with custom paths
  pwsh -File .\Sort-Downloads.ps1 -Downloads 'C:\Users\YourName\Downloads' -Movies 'D:\Movies'

.EXAMPLE
  # Run with confirmation prompts for each move
  pwsh -File .\Sort-Downloads.ps1 -Confirm

.NOTES
  BEGINNER TIPS:
  - Always run with -WhatIf first to see what will happen
  - The ! prefix on folder names makes them sort to the top in Windows Explorer
  - Check the CSV log if you can't find something after running
  - Items already in the helper folders won't be moved again
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [string]$Downloads = 'D:\Users\felix\Downloads',  # TODO: Change this to your actual Downloads path
  [string]$Movies    = 'I:\Movies'                  # TODO: Change this to your Movies folder path
)

# =============================================================================
# FOLDER SETUP - Where different file types will be organized
# =============================================================================

Write-Host "🗂️  Setting up organization folders..." -ForegroundColor Cyan

# Helper folders that will be created in your Downloads directory
$LogsRoot   = Join-Path $Downloads '_SortLogs'              # CSV logs of what was moved
$PDFRoot    = Join-Path $Downloads '!PDFs'                  # Parent folder for PDFs
$PDFToSort  = Join-Path $PDFRoot 'ToSort'                   # Unsorted PDFs go here
$Quarantine = Join-Path $Downloads '!Installers_Quarantine' # Software installers (review before running!)
$PicReview  = Join-Path $Downloads '!Pictures_Review'       # Images to sort later
$TBD        = Join-Path $Downloads '!_TBD'                  # "To Be Determined" - misc files
$ArcReview  = Join-Path $Downloads '!Archives_Review'       # ZIP/RAR files to review

# Folder names to ignore (won't be moved since they're our organization system)
$floatNames = @('_SortLogs','!PDFs','!Installers_Quarantine','!Pictures_Review','!_TBD','!Archives_Review')

# Create all necessary folders if they don't exist
Write-Verbose "Creating organization folders..."
$ensure = @($LogsRoot,$PDFRoot,$PDFToSort,$Quarantine,$PicReview,$TBD,$ArcReview,$Movies)
foreach($p in $ensure){ 
  if(-not (Test-Path $p)){ 
    Write-Verbose "Creating folder: $p"
    New-Item -ItemType Directory -Path $p -Force | Out-Null 
  }
}

# =============================================================================
# FILE TYPE DEFINITIONS - What goes where
# =============================================================================

# Movie files (go to Movies folder)
$movieExt = '.mkv','.mp4','.mov','.avi','.m4v','.m2ts','.ts','.iso','.wmv','.flv','.webm'

# Image files (go to Pictures Review)
$imgExt = '.jpg','.jpeg','.png','.gif','.webp','.heic','.bmp','.tiff','.svg'

# Software installers (go to Quarantine for security review)
$instExt = '.exe','.msi','.msix','.appx','.deb','.rpm','.dmg'

# PDF documents
$pdfExt = '.pdf'

# Archive files (ZIP, RAR, etc.)
$arcExt = '.zip','.rar','.7z','.tar','.gz','.xz','.7zip','.bz2'

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

<#
.SYNOPSIS
  Checks if a folder contains movie files (searches recursively)
.DESCRIPTION
  This function looks inside a folder and all its subfolders to see if there are any movie files.
  Useful for identifying downloaded TV show seasons, movie collections, etc.
#>
function Test-FolderHasMovie {
  param([Parameter(Mandatory)][string]$Path)
  
  Write-Verbose "Scanning folder for movies: $Path"
  try {
    # Look for any movie files inside this folder (including subfolders)
    $movieFile = Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
                 Where-Object { $movieExt -contains $_.Extension.ToLower() } |
                 Select-Object -First 1
    
    if ($movieFile) {
      Write-Verbose "Found movie file: $($movieFile.Name)"
      return $true
    }
    return $false
  } catch { 
    Write-Warning "Couldn't scan folder $Path : $($_.Exception.Message)"
    return $false 
  }
}

<#
.SYNOPSIS
  Safely moves a file/folder to destination, handling name conflicts
.DESCRIPTION
  If the destination already has a file with the same name, this adds a timestamp
  to make it unique. This prevents accidental overwrites.
#>
function Move-Safe {
  param(
    [Parameter(Mandatory)][string]$Path,    # What to move
    [Parameter(Mandatory)][string]$Dest     # Where to move it
  )
  
  # Check if source still exists (might have been moved already)
  if(-not (Test-Path $Path)){ 
    Write-Verbose "Source no longer exists: $Path"
    return $null 
  }
  
  $leaf = Split-Path $Path -Leaf  # Get just the filename/foldername
  $target = Join-Path $Dest $leaf
  
  # Handle name conflicts by adding timestamp
  if(Test-Path $target){
    Write-Verbose "Name conflict detected, adding timestamp..."
    $name = [IO.Path]::GetFileNameWithoutExtension($leaf)
    $ext  = [IO.Path]::GetExtension($leaf)
    $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $target = Join-Path $Dest ("{0}__{1}{2}" -f $name,$timestamp,$ext)
  }
  
  # Actually perform the move (respects -WhatIf parameter)
  if ($PSCmdlet.ShouldProcess("$Path","Move to $target")) {
    try {
      Move-Item -LiteralPath $Path -Destination $target -Force
      Write-Verbose "✅ Moved: $leaf -> $target"
    } catch {
      Write-Error "❌ Failed to move $Path : $($_.Exception.Message)"
      return $null
    }
  }
  
  return $target
}

# =============================================================================
# MAIN SORTING LOGIC
# =============================================================================

Write-Host "📁 Scanning Downloads folder: $Downloads" -ForegroundColor Yellow

# Get all items in Downloads (but ignore our organization folders)
$items = Get-ChildItem -LiteralPath $Downloads -Force -ErrorAction SilentlyContinue |
         Where-Object { $floatNames -notcontains $_.Name }

if (-not $items) {
  Write-Host "✨ Downloads folder is already clean! Nothing to sort." -ForegroundColor Green
  exit 0
}

Write-Host "Found $($items.Count) items to process..." -ForegroundColor Yellow

# Setup logging
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $LogsRoot "sort-$timestamp.csv"
$logEntries = New-Object System.Collections.Generic.List[object]

Write-Host "📝 Results will be logged to: $logPath" -ForegroundColor Gray

# Process each item
foreach($item in $items){
  try {
    $destination = $null
    $reason = $null
    $isDirectory = $item.PSIsContainer
    $itemName = $item.Name

    Write-Host "🔍 Processing: $itemName" -ForegroundColor White

    if($isDirectory){
      # It's a folder - check if it contains movies
      if (Test-FolderHasMovie -Path $item.FullName) {
        $destination = $Movies
        $reason = 'Folder contains movie files'
        Write-Host "  📽️  -> Movies (contains video files)" -ForegroundColor Magenta
      } else {
        $destination = $TBD
        $reason = 'Folder without movies -> needs manual review'
        Write-Host "  📂 -> To Be Determined (unknown folder type)" -ForegroundColor Yellow
      }
    } else {
      # It's a file - categorize by extension
      $extension = $item.Extension.ToLower()
      
      if ($movieExt -contains $extension) {
        $destination = $Movies
        $reason = 'Movie file'
        Write-Host "  🎬 -> Movies" -ForegroundColor Magenta
      }
      elseif ($pdfExt -contains $extension) {
        $destination = $PDFToSort
        $reason = 'PDF document'
        Write-Host "  📄 -> PDFs/ToSort" -ForegroundColor Blue
      }
      elseif ($imgExt -contains $extension) {
        $destination = $PicReview
        $reason = 'Image file'
        Write-Host "  🖼️  -> Pictures Review" -ForegroundColor Green
      }
      elseif ($instExt -contains $extension) {
        $destination = $Quarantine
        $reason = 'Software installer (security review recommended)'
        Write-Host "  ⚠️  -> Installers Quarantine (SCAN BEFORE RUNNING!)" -ForegroundColor Red
      }
      elseif ($arcExt -contains $extension) {
        $destination = $ArcReview
        $reason = 'Archive file'
        Write-Host "  📦 -> Archives Review" -ForegroundColor Cyan
      }
      else {
        $destination = $TBD
        $reason = "Unrecognized file type ($extension)"
        Write-Host "  ❓ -> To Be Determined (unknown file type)" -ForegroundColor Yellow
      }
    }

    # Perform the actual move
    $finalPath = Move-Safe -Path $item.FullName -Dest $destination

    # Log this operation
    $logEntries.Add([pscustomobject]@{
      Timestamp    = Get-Date
      OriginalPath = $item.FullName
      Destination  = $destination
      FinalPath    = $finalPath
      Reason       = $reason
      Type         = if($isDirectory){'Folder'} else {'File'}
      Extension    = if($isDirectory){'N/A'} else {$item.Extension}
    }) | Out-Null

  } catch {
    # Something went wrong - log the error
    Write-Error "❌ Failed to process $($item.FullName): $($_.Exception.Message)"
    
    $logEntries.Add([pscustomobject]@{
      Timestamp    = Get-Date
      OriginalPath = $item.FullName
      Destination  = '(FAILED)'
      FinalPath    = $null
      Reason       = "ERROR: $($_.Exception.Message)"
      Type         = if($item.PSIsContainer){'Folder'} else {'File'}
      Extension    = if($item.PSIsContainer){'N/A'} else {$item.Extension}
    }) | Out-Null
  }
}

# =============================================================================
# WRAP UP AND REPORTING
# =============================================================================

# Save the log file
try {
  $logEntries | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath $logPath
  Write-Host "`n📊 SUMMARY:" -ForegroundColor Green
  Write-Host "✅ Processed $($items.Count) items" -ForegroundColor Green
  Write-Host "📝 Detailed log saved to: $logPath" -ForegroundColor Gray
  
  # Show summary by category
  $summary = $logEntries | Group-Object Destination | Sort-Object Name
  foreach ($group in $summary) {
    $count = $group.Count
    $dest = Split-Path $group.Name -Leaf
    Write-Host "   $dest`: $count items" -ForegroundColor White
  }
  
} catch {
  Write-Error "Failed to save log file: $($_.Exception.Message)"
}

Write-Host "`n🎉 Downloads sorting complete!" -ForegroundColor Green
Write-Host "💡 TIP: Use -WhatIf next time to preview changes before running." -ForegroundColor Cyan

# Final reminder about security
$installerCount = ($logEntries | Where-Object { $_.Destination -eq $Quarantine }).Count
if ($installerCount -gt 0) {
  Write-Host "`n⚠️  SECURITY REMINDER: $installerCount installer(s) moved to quarantine." -ForegroundColor Red
  Write-Host "   Always scan with antivirus before running executable files!" -ForegroundColor Red
}