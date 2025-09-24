<# 
.SYNOPSIS
    Discovers and audits Git repositories across your system with comprehensive status reporting.

.DESCRIPTION
    GitAudit scans specified directories (or entire drives) to find Git repositories
    and reports their status including branch, origin, upstream tracking, dirty state,
    and push status. Supports nested repository detection and flexible scanning options.
    
    The script uses a two-phase approach:
    1. Quick Discovery - Fast scan using Get-ChildItem with recursion
    2. Deep Scanning - Breadth-first search with custom exclusions (if quick scan fails)
    
    Configuration files allow you to save your preferred settings for regular use.

.PARAMETER Roots
    Array of root directories to scan. Defaults to $HOME if not specified.
    Supports both forward and backward slashes on Windows.
    Examples: 'C:\Projects', 'D:\Code', '/home/user/dev'
    Position: 0 (can be used without parameter name)

.PARAMETER AllFixedDrives
    Switch parameter. Scan all fixed drives instead of specific root directories.
    Useful for initial discovery of all repositories on your system.

.PARAMETER MaxDepth
    Maximum directory depth to recurse during deep scanning. Default: 6 levels.
    Higher values = more thorough but slower scans. Range: 1-20.
    Example: -MaxDepth 4 for faster scans of typical project structures.

.PARAMETER MaxDirs
    Maximum number of directories to scan before stopping. Default: 150,000.
    Prevents runaway scans on large filesystems. Range: 1000-1000000.

.PARAMETER SkipJunctions
    Switch parameter. Skip symbolic links and junctions. Default: $true.
    Set to $false to follow symlinks (may cause infinite loops on misconfigured systems).

.PARAMETER ExcludeDir
    Array of directory names to exclude from scanning. 
    Default excludes system folders and common build/cache directories.
    Add custom exclusions for your environment.

.PARAMETER LogFile
    Write results to a log file in addition to console output.
    Useful for historical tracking, automated workflows, and troubleshooting.
    Default creates timestamped log in script directory if not specified.

.PARAMETER AppendLog
    Switch parameter. Append to existing log file instead of overwriting.
    Use for maintaining historical logs across multiple script runs.

.PARAMETER ShowNested
    Switch parameter. Flag repositories that are nested inside other repositories.
    Helps identify submodules or accidentally nested repositories.

.PARAMETER LocalMode
    Switch parameter. Skip remote operations for faster scanning and offline use.
    When enabled, skips: origin URL checking, push status, ahead/behind counts.
    Use when internet is unavailable or for very fast local-only status checks.

.PARAMETER QuietMode
    Switch parameter. Suppress progress messages and non-essential output.
    Useful for scripting or when you only want the final results.

.PARAMETER ConfigFile
    Path to configuration file. Default: gitaudit.config.json in script directory.
    Allows multiple configuration profiles for different scanning scenarios.

.PARAMETER SaveConfig
    Switch parameter. Save current parameters to configuration file for future use.
    Creates a JSON file with your current settings for easy reuse.

.PARAMETER ShowConfig
    Switch parameter. Display current configuration file contents and exit.
    Useful for reviewing saved settings before running a scan.

.PARAMETER CreateDefaultConfig
    Switch parameter. Create a sensible default configuration file with common settings.
    Good starting point for most users - scans common development directories.

.PARAMETER Help
    Switch parameter. Display detailed help and usage examples.

.EXAMPLE
    .\gitaudit.ps1
    Scan user home directory with default settings, or use saved configuration if available.

.EXAMPLE
    .\gitaudit.ps1 'C:\Projects' 'D:\Code'
    Scan specific directories using positional parameters (no -Roots needed).

.EXAMPLE
    .\gitaudit.ps1 -Roots 'C:\Projects','D:\Code' -MaxDepth 4
    Scan specific directories with custom depth limit using named parameters.

.EXAMPLE
    .\gitaudit.ps1 -AllFixedDrives -CsvOut 'all-repos.csv' -ShowNested
    Comprehensive scan: all drives, export to CSV, flag nested repositories.

.EXAMPLE
    .\gitaudit.ps1 -LogFile 'git-audit.log' -AppendLog
    Scan using saved config and append results to a persistent log file.

.EXAMPLE
    .\gitaudit.ps1 'C:\Projects' -CsvOut 'weekly-report.csv' -LogFile 'audit.log'
    Scan specific directory, export CSV, and log results for record-keeping.

.EXAMPLE
    .\gitaudit.ps1 -CreateDefaultConfig
    Create a sensible default configuration file for typical development environments.

.EXAMPLE
    .\gitaudit.ps1 -Roots 'C:\Work' -SaveConfig
    Scan work directories and save these settings as default configuration.

.EXAMPLE
    .\gitaudit.ps1 -ConfigFile 'work-repos.json' -ShowConfig
    Display configuration from a specific config file.

.EXAMPLE
    .\gitaudit.ps1 -Help
    Show comprehensive help and usage information.

.NOTES
    Version: 2.0
    Requires: PowerShell 5.1+ and Git in PATH
    Author: Enhanced version with comprehensive PowerShell learning documentation
    
    PowerShell Learning Notes:
    - [CmdletBinding()] enables advanced function features like -Verbose, -Debug
    - param() block defines all parameters with validation and help
    - [Parameter()] attributes control parameter behavior
    - [switch] parameters are boolean flags (present = true, absent = false)
    - Position=0 allows positional parameter usage
    - ValidateRange() ensures parameters are within acceptable bounds
    - ParameterSetName groups related parameters and enables mutual exclusivity
    
    Configuration files use ConvertTo-Json/ConvertFrom-Json for serialization.
    Progress indicators use Write-Progress with activity, status, and percentage.
    Error handling uses try/catch blocks with specific error actions.
#>

# PowerShell CmdletBinding enables advanced function features like -Verbose, -Debug, -WhatIf
# DefaultParameterSetName specifies which parameter set to use when ambiguous
[CmdletBinding(DefaultParameterSetName='Scan')]
param(
    # Position=0 means this parameter can be used without the parameter name
    # Alias allows shorter parameter names for convenience
    [Parameter(ParameterSetName='Scan', Position=0)]
    [Alias('Path', 'Directory', 'Dir')]
    [string[]] $Roots,
    
    # Switch parameters are boolean - present means $true, absent means $false
    [Parameter(ParameterSetName='Scan')]
    [switch] $AllFixedDrives,
    
    # ValidateRange ensures the parameter value is within acceptable bounds
    [Parameter(ParameterSetName='Scan')]
    [ValidateRange(1,20)]
    [int] $MaxDepth = 6,
    
    [Parameter(ParameterSetName='Scan')]
    [ValidateRange(1000,1000000)]
    [int] $MaxDirs = 150000,
    
    # Default value of $true for switch parameters means it's on by default
    [Parameter(ParameterSetName='Scan')]
    [switch] $SkipJunctions,
    
    # Array parameters can accept multiple values: -ExcludeDir 'folder1','folder2'
    [Parameter(ParameterSetName='Scan')]
    [string[]] $ExcludeDir = @('Windows','Program Files','Program Files (x86)','ProgramData',
                               '$Recycle.Bin','System Volume Information','Recovery',
                               'OneDriveTemp','Temp','AppData','node_modules','.venv','.git',
                               'vendor','dist','build','target','bin','obj'),
    
    [Parameter(ParameterSetName='Scan')]
    [string] $CsvOut,
    
    [Parameter(ParameterSetName='Scan')]
    [string] $LogFile,
    
    [Parameter(ParameterSetName='Scan')]
    [switch] $AppendLog,
    
    [Parameter(ParameterSetName='Scan')]
    [switch] $ShowNested,
    
    # NEW: LocalMode for offline/fast scanning
    [Parameter(ParameterSetName='Scan')]
    [switch] $LocalMode,
    
    [Parameter(ParameterSetName='Scan')]
    [switch] $QuietMode,
    
    [Parameter(ParameterSetName='Scan')]
    [string] $ConfigFile,
    
    # Config operations use a separate parameter set to prevent conflicts
    [Parameter(ParameterSetName='Config')]
    [switch] $SaveConfig,
    
    [Parameter(ParameterSetName='Config')]
    [switch] $ShowConfig,
    
    [Parameter(ParameterSetName='Config')]
    [switch] $CreateDefaultConfig,
    
    # Help uses its own parameter set for clean separation
    [Parameter(ParameterSetName='Help')]
    [switch] $Help
)

function Show-Help {
    $helpText = @"

=== Git Audit Tool - Comprehensive Help ===

OVERVIEW:
    GitAudit discovers Git repositories and reports their status, including:
    • Branch information and tracking status
    • Remote origin configuration  
    • Push/pull status (ahead/behind)
    • Working directory cleanliness
    • Nested repository detection

BASIC USAGE:
    .\gitaudit.ps1                             # Scan home directory or use saved config
    .\gitaudit.ps1 'C:\Projects'               # Scan specific directory (positional)
    .\gitaudit.ps1 -AllFixedDrives             # Scan all drives
    .\gitaudit.ps1 -Help                       # Show this help

CONFIGURATION FILE USAGE:
    .\gitaudit.ps1 -CreateDefaultConfig        # Create sensible defaults
    .\gitaudit.ps1                             # Use created/saved config
    .\gitaudit.ps1 -ShowConfig                 # Display current config
    .\gitaudit.ps1 -ConfigFile 'work.json'    # Use specific config file

    RECOMMENDED FIRST-TIME SETUP:
    1. .\gitaudit.ps1 -CreateDefaultConfig     # Creates smart defaults
    2. .\gitaudit.ps1                          # Test the default config
    3. Edit gitaudit.config.json to customize # Fine-tune as needed
       • Add LogFile: "git-audit.log" for automatic logging
       • Set AppendLog: true to maintain history

COMMON SCENARIOS:

1. First Time Setup (Discovery):
   .\gitaudit.ps1 -AllFixedDrives -MaxDepth 4 -CsvOut 'all-repos.csv'

2. Save Your Development Areas:
   .\gitaudit.ps1 'C:\Projects' 'D:\Code' 'C:\MyStuff' -SaveConfig

3. Regular Quick Check:
   .\gitaudit.ps1                             # Uses saved config

4. Fast Local-Only Check (no internet needed):
   .\gitaudit.ps1 -LocalMode

5. Multiple Configurations:
   .\gitaudit.ps1 'C:\Work' -ConfigFile 'work.json' -SaveConfig
   .\gitaudit.ps1 -ConfigFile 'work.json'

LOCAL MODE:
    Use -LocalMode for faster scanning when:
    • Internet connection is slow/unavailable
    • You only need local status (branch, dirty state)
    • Scanning many repositories quickly
    
    Local mode skips: origin URLs, push status, ahead/behind counts

PERFORMANCE TUNING:
    • Reduce -MaxDepth for faster scans (3-4 for most projects)
    • Use -LocalMode for fastest possible scans
    • Add folders to -ExcludeDir to skip irrelevant areas
    • Save targeted -Roots in config file for regular use
    • Use -QuietMode to reduce output overhead

OUTPUT COLUMNS:
    RepoRoot  - Full path to repository
    Branch    - Current branch name
    Origin    - Remote origin URL (LocalMode: skipped)
    Upstream  - Upstream tracking branch (LocalMode: local only)
    Ahead     - Commits ahead of upstream (LocalMode: 0)
    Behind    - Commits behind upstream (LocalMode: 0)
    Pushed    - Whether current branch exists on origin (LocalMode: skipped)
    Dirty     - Whether working directory has changes
    Nested    - Whether repo is inside another repo (if -ShowNested used)

POWERSHELL LEARNING NOTES:
    • Parameters can be positional: .\gitaudit.ps1 'C:\Code'
    • Or named: .\gitaudit.ps1 -Roots 'C:\Code'
    • Switch parameters don't need values: -LocalMode (not -LocalMode `$true)
    • Arrays use comma separation: 'folder1','folder2'
    • Paths accept forward or backward slashes on Windows
    • Config files are JSON format for easy editing

TROUBLESHOOTING:
    • Ensure Git is installed and in PATH
    • Run PowerShell as Administrator for system-wide scans
    • Use -LocalMode if Git operations hang or timeout
    • Increase -MaxDirs if scan stops with "Reached MaxDirs" warning
    • Check -ExcludeDir if important repositories are being skipped

"@
    Write-Host $helpText -ForegroundColor Green
    return
}

if ($Help) { Show-Help; return }

# PowerShell automatic variables:
# $MyInvocation - Information about how the script was invoked
# $MyInvocation.MyCommand.Path - Full path to the current script file
# Split-Path -Parent gets the directory containing the script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Join-Path safely combines path components regardless of trailing slashes
# Config file is ALWAYS next to the script, regardless of current directory
$defaultConfigPath = Join-Path $scriptDir 'gitaudit.config.json'

# PowerShell conditional assignment: if $ConfigFile is empty/null, use default
if (-not $ConfigFile) { $ConfigFile = $defaultConfigPath }

# DEBUG: Show parameter values for troubleshooting
Write-Host "DEBUG Parameter Values:" -ForegroundColor Magenta
Write-Host "  Roots: $($Roots -join ', ')" -ForegroundColor Gray
Write-Host "  ConfigFile: $ConfigFile" -ForegroundColor Gray
Write-Host "  CreateDefaultConfig: $CreateDefaultConfig" -ForegroundColor Gray
Write-Host "  PSBoundParameters Keys: $($PSBoundParameters.Keys -join ', ')" -ForegroundColor Gray

# Ensure ConfigFile is always a file path, not a directory
if (Test-Path $ConfigFile -PathType Container) {
    # If someone passed a directory, append the default filename
    $ConfigFile = Join-Path $ConfigFile 'gitaudit.config.json'
    Write-Host "  ConfigFile corrected to: $ConfigFile" -ForegroundColor Gray
}

# DEBUG: Show where config file will be located (helpful for learning)
if (-not $QuietMode) {
    Write-Host "Config file location: $ConfigFile" -ForegroundColor Gray
}

# PowerShell functions can have multiple parameters and support advanced features
function Save-Configuration {
    param($Path)  # Simple parameter - just needs a path string
    
    # Create a hashtable (@{}) to store configuration data
    # Hashtables are key-value pairs, like objects in other languages
    $config = @{
        Roots = $Roots
        AllFixedDrives = $AllFixedDrives.IsPresent  # .IsPresent checks if switch was used
        MaxDepth = $MaxDepth
        MaxDirs = $MaxDirs
        SkipJunctions = $SkipJunctions.IsPresent
        ExcludeDir = $ExcludeDir
        ShowNested = $ShowNested.IsPresent
        LocalMode = $LocalMode.IsPresent
        QuietMode = $QuietMode.IsPresent
        LogFile = $LogFile
        AppendLog = $AppendLog.IsPresent
        # Get-Date with -Format creates a formatted timestamp
        SavedDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        # Environment variables accessed via $env: drive
        SavedBy = $env:USERNAME
    }
    
    try {
        # Pipeline: $config | ConvertTo-Json | Set-Content
        # ConvertTo-Json serializes the hashtable to JSON format
        # -Depth 3 ensures nested objects are properly serialized
        # Set-Content writes the JSON string to file with UTF8 encoding
        $config | ConvertTo-Json -Depth 3 | Set-Content -Path $Path -Encoding UTF8
        Write-Host "Configuration saved to: $Path" -ForegroundColor Green
        Write-Host "Use without parameters to load this config automatically." -ForegroundColor Yellow
    } catch {
        # $_ represents the current error object in catch blocks
        # .Exception.Message gets the human-readable error message
        Write-Error "Failed to save configuration: $($_.Exception.Message)"
    }
}

function Get-Configuration {
    param($Path)  # Function parameter - path to config file
    
    # Test-Path checks if file exists before trying to read it
    if (-not (Test-Path $Path)) { return $null }
    
    try {
        # Pipeline: Get-Content | ConvertFrom-Json
        # Get-Content reads the entire file as text
        # ConvertFrom-Json deserializes JSON text back into PowerShell objects
        $config = Get-Content -Path $Path -Encoding UTF8 | ConvertFrom-Json
        Write-Host "Loaded configuration from: $Path" -ForegroundColor Green
        
        # PowerShell object property access using dot notation
        if ($config.SavedDate) {
            Write-Host "  Saved: $($config.SavedDate) by $($config.SavedBy)" -ForegroundColor Gray
        }
        return $config
    } catch {
        # Write-Warning shows yellow warning text, doesn't stop execution
        Write-Warning "Failed to load configuration from $Path : $($_.Exception.Message)"
        return $null
    }
}

function New-DefaultConfiguration {
    param($Path)
    
    # Create a sensible default configuration for typical development environments
    # This analyzes the system and creates smart defaults
    
    Write-Host "Creating default configuration..." -ForegroundColor Cyan
    
    # Common development directories to check (if they exist)
    $potentialRoots = @()
    $commonDevPaths = @(
        "$env:USERPROFILE\Documents\GitHub",
        "$env:USERPROFILE\source\repos",
        "$env:USERPROFILE\dev",
        "$env:USERPROFILE\development", 
        "$env:USERPROFILE\projects",
        "$env:USERPROFILE\code",
        "C:\dev",
        "C:\projects", 
        "C:\source",
        "C:\git",
        "C:\github",
        "D:\dev",
        "D:\projects",
        "D:\source",
        "D:\git",
        "D:\github"
    )
    
    Write-Host "Checking for common development directories..." -ForegroundColor Yellow
    foreach ($devPath in $commonDevPaths) {
        if (Test-Path -LiteralPath $devPath) {
            $potentialRoots += $devPath
            Write-Host "  Found: $devPath" -ForegroundColor Green
        }
    }
    
    # If no common dev directories found, fall back to user profile
    if ($potentialRoots.Count -eq 0) {
        $potentialRoots = @($env:USERPROFILE)
        Write-Host "  No common dev directories found, using: $env:USERPROFILE" -ForegroundColor Yellow
    }
    
    # Create default configuration with smart settings
    $defaultConfig = @{
        Roots = $potentialRoots
        AllFixedDrives = $false
        MaxDepth = 4  # Good balance of thoroughness vs speed for most projects
        MaxDirs = 50000  # Lower than max for faster scans in typical scenarios
        SkipJunctions = $true
        ExcludeDir = @(
            # System directories
            'Windows','Program Files','Program Files (x86)','ProgramData',
            '$Recycle.Bin','System Volume Information','Recovery',
            # Temp and cache directories
            'OneDriveTemp','Temp','AppData','LocalAppData',
            # Development build/dependency directories  
            'node_modules','.venv','venv','env','__pycache__',
            'vendor','dist','build','target','bin','obj','out',
            # Version control (don't scan inside .git)
            '.git','.svn',
            # IDE directories
            '.vscode','.idea','*.tmp'
        )
        ShowNested = $false  # Can be enabled later if needed
        LocalMode = $false   # Default to full functionality
        QuietMode = $false   # Show progress by default
        LogFile = ""         # No default logging, user can specify
        AppendLog = $true    # Default to appending for historical logs
        SavedDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        SavedBy = $env:USERNAME
        ConfigType = "Default Generated Configuration"
        Notes = "Auto-generated default config. Edit this file directly to customize settings."
    }
    
    try {
        Write-Host "Attempting to save config to: $Path" -ForegroundColor Gray
        
        # Ensure the directory exists
        $parentDir = Split-Path -Parent $Path
        if (-not (Test-Path $parentDir)) {
            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
        }
        
        # Ensure we're writing to a file, not a directory
        if (Test-Path $Path -PathType Container) {
            throw "Config path '$Path' is a directory, not a file. Expected a file path ending in .json"
        }
        
        $defaultConfig | ConvertTo-Json -Depth 3 | Set-Content -Path $Path -Encoding UTF8
        Write-Host "`nDefault configuration created successfully!" -ForegroundColor Green
        Write-Host "Config file: $Path" -ForegroundColor Gray
        Write-Host "`nConfiguration includes:" -ForegroundColor Yellow
        Write-Host "  • Scan roots: $($potentialRoots -join ', ')"
        Write-Host "  • Max depth: 4 levels (good for most projects)"
        Write-Host "  • Excludes: System folders + common build/cache directories"
        Write-Host "`nNext steps:" -ForegroundColor Cyan
        Write-Host "  1. Run: .\gitaudit.ps1                    # Test the default config"
        Write-Host "  2. Edit: $Path            # Customize as needed"
        Write-Host "  3. Run: .\gitaudit.ps1 -ShowConfig        # Review your settings"
        
    } catch {
        Write-Error "Failed to create default configuration: $($_.Exception.Message)"
        Write-Host "Debug info:" -ForegroundColor Yellow
        Write-Host "  Attempted path: $Path" -ForegroundColor Gray
        Write-Host "  Path exists: $(Test-Path $Path)" -ForegroundColor Gray
        Write-Host "  Is container: $(Test-Path $Path -PathType Container)" -ForegroundColor Gray
    }
}

function Show-Configuration {
    param($Path)
    
    if (-not (Test-Path $Path)) {
        Write-Host "No configuration file found at: $Path" -ForegroundColor Yellow
        return
    }
    
    $config = Get-Configuration -Path $Path
    if ($config) {
        Write-Host "`n=== Current Configuration ===" -ForegroundColor Cyan
        Write-Host "Config File: $Path"
        
        # String interpolation: $() allows expressions inside strings
        # -join converts arrays to comma-separated strings for display
        Write-Host "Roots: $($config.Roots -join ', ')"
        Write-Host "AllFixedDrives: $($config.AllFixedDrives)"
        Write-Host "MaxDepth: $($config.MaxDepth)"
        Write-Host "MaxDirs: $($config.MaxDirs)"
        Write-Host "SkipJunctions: $($config.SkipJunctions)"
        Write-Host "ExcludeDir: $($config.ExcludeDir -join ', ')"
        Write-Host "ShowNested: $($config.ShowNested)"
        Write-Host "LocalMode: $($config.LocalMode)"
        Write-Host "QuietMode: $($config.QuietMode)"
        Write-Host "LogFile: $($config.LogFile)"
        Write-Host "AppendLog: $($config.AppendLog)"
        
        if ($config.SavedDate) {
            Write-Host "Saved: $($config.SavedDate) by $($config.SavedBy)"
        }
    }
}

# Handle config-only operations first (before parameter processing)
# Force the config path to always be the correct location for config operations
if ($ShowConfig -or $CreateDefaultConfig -or $SaveConfig) {
    # For config operations, always use the default path next to the script
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $forceConfigPath = Join-Path $scriptDir 'gitaudit.config.json'
    Write-Host "DEBUG: Forcing config path to: $forceConfigPath" -ForegroundColor Magenta
    
    if ($ShowConfig) { 
        Show-Configuration -Path $forceConfigPath; return 
    }
    if ($CreateDefaultConfig) { 
        New-DefaultConfiguration -Path $forceConfigPath; return 
    }
    if ($SaveConfig) { 
        Save-Configuration -Path $forceConfigPath; return 
    }
}

# Load configuration if no explicit parameters provided and config exists
# This creates smart defaults while still allowing parameter overrides
$usingConfig = $false

# $PSBoundParameters is an automatic hashtable containing all explicitly provided parameters
# .ContainsKey() checks if a specific parameter was provided by the user
if ((-not $PSBoundParameters.ContainsKey('Roots')) -and 
    (-not $PSBoundParameters.ContainsKey('AllFixedDrives')) -and 
    (Test-Path $ConfigFile)) {
    
    $config = Get-Configuration -Path $ConfigFile
    if ($config) {
        # Conditional assignment: only use config values if user didn't specify them
        # This allows command-line parameters to override saved configuration
        if ((-not $PSBoundParameters.ContainsKey('Roots')) -and $config.Roots) { 
            $Roots = $config.Roots 
        }
        if ((-not $PSBoundParameters.ContainsKey('AllFixedDrives')) -and $config.AllFixedDrives) { 
            $AllFixedDrives = $true 
        }
        if ((-not $PSBoundParameters.ContainsKey('MaxDepth')) -and $config.MaxDepth) { 
            $MaxDepth = $config.MaxDepth 
        }
        if ((-not $PSBoundParameters.ContainsKey('MaxDirs')) -and $config.MaxDirs) { 
            $MaxDirs = $config.MaxDirs 
        }
        # $null comparison needed for boolean values since $false is "falsy" in PowerShell
        if ((-not $PSBoundParameters.ContainsKey('SkipJunctions')) -and ($null -ne $config.SkipJunctions)) { 
            $SkipJunctions = $config.SkipJunctions 
        }
        if ((-not $PSBoundParameters.ContainsKey('ExcludeDir')) -and $config.ExcludeDir) { 
            $ExcludeDir = $config.ExcludeDir 
        }
        if ((-not $PSBoundParameters.ContainsKey('ShowNested')) -and $config.ShowNested) { 
            $ShowNested = $true 
        }
        if ((-not $PSBoundParameters.ContainsKey('LocalMode')) -and $config.LocalMode) { 
            $LocalMode = $true 
        }
        if ((-not $PSBoundParameters.ContainsKey('QuietMode')) -and $config.QuietMode) { 
            $QuietMode = $true 
        }
        if ((-not $PSBoundParameters.ContainsKey('LogFile')) -and $config.LogFile) { 
            $LogFile = $config.LogFile 
        }
        if ((-not $PSBoundParameters.ContainsKey('AppendLog')) -and $config.AppendLog) { 
            $AppendLog = $true 
        }
    }
}

# Default to SkipJunctions=true if not explicitly set
if (-not $PSBoundParameters.ContainsKey('SkipJunctions')) {
    $SkipJunctions = $true
}

# Parameter validation and setup with detailed PowerShell learning comments

# Default to user's home directory if no roots specified and not scanning all drives
# $HOME is a PowerShell automatic variable containing the user's home directory path
if (-not $Roots -and -not $AllFixedDrives) { $Roots = @($HOME) }

# PowerShell array iteration using for loop with .Count property
# Regular expression matching: -match operator uses regex patterns
# String interpolation: "$(...)" allows expressions inside strings
for ($i = 0; $i -lt $Roots.Count; $i++) { 
    # Match pattern: starts with letter, followed by colon, then end of string
    if ($Roots[$i] -match '^[A-Za-z]:$') { 
        $Roots[$i] = "$($Roots[$i])\" 
    } 
}

# If AllFixedDrives is specified, get all fixed drives from the system
if ($AllFixedDrives) { 
    # [IO.DriveInfo]::GetDrives() - Static method call to get all system drives
    # Pipeline with Where-Object (? is alias) to filter results
    # -eq comparison operator (case-insensitive by default in PowerShell)
    # -and logical operator to combine conditions
    $Roots = ([IO.DriveInfo]::GetDrives() | Where-Object { 
        $_.DriveType -eq 'Fixed' -and $_.IsReady 
    }).RootDirectory.FullName 
}

# Set up logging if requested
$logOutput = @()
if ($LogFile -or $PSBoundParameters.ContainsKey('LogFile')) {
    # Set default log file if -LogFile was used without a value
    if (-not $LogFile) {
        $timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
        $LogFile = Join-Path $scriptDir "gitaudit_$timestamp.log"
    }
    
    # Ensure log directory exists
    $logDir = Split-Path -Parent $LogFile
    if ($logDir -and -not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    
    if (-not $QuietMode) {
        $appendText = if ($AppendLog) { " (appending)" } else { " (overwriting)" }
        Write-Host "Logging to: $LogFile$appendText" -ForegroundColor Gray
    }
}

# Helper function to write both to console and log
function Write-LogOutput {
    param([string]$Message, [string]$ForegroundColor = 'White')
    
    Write-Host $Message -ForegroundColor $ForegroundColor
    if ($LogFile) {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $script:logOutput += "[$timestamp] $Message"
    }
}

# Verify Git is available using Get-Command with error handling
# -ErrorAction SilentlyContinue suppresses error output
# -not operator negates the result (true becomes false, false becomes true)
if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { 
    Write-Error "Git is not installed or not in PATH. Please install Git and try again."
    return  # Exit the script early if Git is not found
}

# Helper function to test if a directory is a Git repository root
# PowerShell function with typed parameter for better error handling
function Test-IsRepoRoot { 
    param([string]$Path) 
    # Join-Path safely combines path components
    # Test-Path with -LiteralPath treats the path as literal (no wildcards)
    Test-Path -LiteralPath (Join-Path $Path '.git') 
}

# Quick discovery function: uses PowerShell's built-in Get-ChildItem recursion
function Find-RepoRootsQuick {
    param([string[]]$ScanRoots)  # Array parameter for multiple root directories
    
    $found = @()  # Initialize empty array using @() syntax
    
    # foreach loop over array elements
    foreach ($root in $ScanRoots) {
        # Skip roots that don't exist
        if (-not (Test-Path -LiteralPath $root)) { continue }
        
        try {
            # Get-ChildItem with -Recurse for recursive directory listing
            # -Directory flag returns only directories (not files)
            # -Force includes hidden directories
            # -ErrorAction SilentlyContinue suppresses access denied errors
            $dirs = Get-ChildItem -Path (Join-Path $root '*') -Directory -Recurse -Force -ErrorAction SilentlyContinue
            
            foreach ($d in $dirs) { 
                if (Test-IsRepoRoot $d.FullName) { 
                    # Array addition: += operator adds element to array
                    $found += $d.FullName 
                } 
            }
        } catch {
            # Empty catch block: ignore errors and continue with next root
        }
    }
    
    # Pipeline: Sort-Object with -Unique removes duplicates and sorts
    $found | Sort-Object -Unique
}

function Find-RepoRootsFull {
    param([string[]]$ScanRoots,[int]$MaxDepth,[int]$MaxDirs,[string[]]$ExcludeDir,[switch]$SkipJunctions,[switch]$QuietMode)
    $found=@{}; $scanned=0; $hits=0
    
    foreach ($start in $ScanRoots) {
        if (-not (Test-Path -LiteralPath $start)) { continue }
        $q = New-Object 'System.Collections.Generic.Queue[object]'
        $q.Enqueue([pscustomobject]@{ Path=$start; Depth=0 })
        
        while ($q.Count -gt 0) {
            $it=$q.Dequeue(); $p=$it.Path; $d=$it.Depth
            $scanned++
            
            if (-not $QuietMode -and $scanned % 1000 -eq 0) { 
                Write-Progress -Activity "Scanning directories..." -Status "$scanned scanned, $hits repos found" -PercentComplete -1 
            }
            
            if ($scanned -ge $MaxDirs) { 
                Write-Warning ("Reached MaxDirs limit ({0}). Consider increasing -MaxDirs or adding more exclusions." -f $MaxDirs)
                break 
            }
            
            if (Test-IsRepoRoot $p) { 
                if (-not $found.ContainsKey($p)) { $found[$p]=$true; $hits++ } 
            }
            
            if ($d -ge $MaxDepth) { continue }
            
            try { $children=[IO.Directory]::EnumerateDirectories($p) } catch { continue }
            
            foreach ($c in $children) {
                $leaf = Split-Path -Path $c -Leaf
                if ($ExcludeDir -contains $leaf) { continue }
                
                if ($SkipJunctions) { 
                    try { 
                        $attrs=[IO.File]::GetAttributes($c)
                        if ($attrs -band [IO.FileAttributes]::ReparsePoint) { continue } 
                    } catch { continue } 
                }
                
                $q.Enqueue([pscustomobject]@{ Path=$c; Depth=$d+1 })
            }
        }
    }
    
    if (-not $QuietMode) { Write-Progress -Activity "Scanning directories..." -Completed }
    $found.Keys | Sort-Object -Unique
}

function GitC {
    param([string]$Path,[string[]]$ArgList,[int]$TimeoutSeconds=30)
    try {
        # Use Start-Process with timeout to prevent hanging
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "git"
        $psi.Arguments = "-C `"$Path`" " + ($ArgList -join " ")
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        
        $process = [System.Diagnostics.Process]::Start($psi)
        
        if ($process.WaitForExit($TimeoutSeconds * 1000)) {
            $output = $process.StandardOutput.ReadToEnd()
            $process.Close()
            if ($output) { $output.Trim() } else { "" }
        } else {
            # Process timed out
            $process.Kill()
            $process.Close()
            Write-Warning "Git command timed out in: $Path"
            ""
        }
    } catch {
        ""
    }
}

function Test-IsNestedRepo {
    param([string]$RepoPath, [string[]]$AllRepoPaths)
    foreach ($other in $AllRepoPaths) {
        if ($other -ne $RepoPath -and $RepoPath.StartsWith($other + [IO.Path]::DirectorySeparatorChar)) {
            return $other
        }
    }
    return $null
}

# Discovery phase
if (-not $QuietMode) { Write-LogOutput "Phase 1: Quick discovery..." -ForegroundColor Cyan }
$repoRoots = Find-RepoRootsQuick -ScanRoots $Roots

if (-not $repoRoots -or $repoRoots.Count -eq 0) {
    if (-not $QuietMode) { Write-LogOutput "Phase 2: Deep scanning..." -ForegroundColor Cyan }
    $repoRoots = Find-RepoRootsFull -ScanRoots $Roots -MaxDepth $MaxDepth -MaxDirs $MaxDirs -ExcludeDir $ExcludeDir -SkipJunctions:$SkipJunctions -QuietMode:$QuietMode
}

if (-not $QuietMode) { Write-LogOutput ("Found {0} repository root(s)." -f ($repoRoots.Count)) -ForegroundColor Cyan }

if (-not $repoRoots -or $repoRoots.Count -eq 0) { 
    Write-LogOutput "No repositories found under: $($Roots -join ', ')" -ForegroundColor Yellow
    Write-LogOutput "Try expanding search with -AllFixedDrives or reducing -ExcludeDir exclusions." -ForegroundColor Yellow
    
    # Write log file even if no repos found
    if ($LogFile) {
        $logContent = $logOutput -join "`n"
        if ($AppendLog -and (Test-Path $LogFile)) {
            Add-Content -Path $LogFile -Value $logContent -Encoding UTF8
        } else {
            Set-Content -Path $LogFile -Value $logContent -Encoding UTF8
        }
    }
    return 
}

# Analysis phase
if (-not $QuietMode) { Write-LogOutput "Phase 3: Analyzing repositories..." -ForegroundColor Cyan }
$rows=@()
$repoCount = 0

foreach ($r in $repoRoots) {
    $repoCount++
    if (-not $QuietMode) { 
        Write-Progress -Activity "Analyzing repositories" -Status "Processing repo $repoCount of $($repoRoots.Count): $r" -PercentComplete (($repoCount / $repoRoots.Count) * 100)
    }
    $inside = GitC -Path $r -ArgList @('rev-parse','--is-inside-work-tree')
    if (($inside -ne 'true') -and -not (Test-IsRepoRoot $r)) { continue }
    
    $branch   = GitC -Path $r -ArgList @('rev-parse','--abbrev-ref','HEAD')
    if (-not $branch) { $branch='(detached or none)' }
    
    $origin   = GitC -Path $r -ArgList @('config','--get','remote.origin.url')
    if (-not $origin) { 
        $origin = '(no origin)' 
    } elseif ($LocalMode) {
        # In LocalMode, don't fetch remote URLs to save time
        $origin = 'Skipped (Local Mode)'
    }
    
    $upstream = GitC -Path $r -ArgList @('rev-parse','--abbrev-ref','--symbolic-full-name','@{u}')
    if (-not $upstream) { $upstream = '(none)' }
    
    $ahead = '0'
    $behind = '0'
    if (-not $LocalMode -and $upstream -ne '(none)') {
        # Only check ahead/behind status if not in LocalMode
        $counts = GitC -Path $r -ArgList @('rev-list','--left-right','--count','HEAD...@{u}')
        if ($counts) { 
            $parts = $counts -split '\s+'
            if ($parts.Count -ge 2) { $ahead = $parts[0]; $behind = $parts[1] } 
        }
    }
    
    $pushed = 'Unknown'
    if (-not $LocalMode -and $origin -ne '(no origin)' -and $branch -ne '(detached or none)') {
        # Only check push status if not in LocalMode (saves time and internet requirements)
        if (GitC -Path $r -ArgList @('ls-remote','--heads','origin',$branch)) { 
            $pushed = 'YES' 
        } else { 
            $pushed = 'NO' 
        }
    } elseif ($LocalMode) {
        # In LocalMode, skip remote operations entirely
        $pushed = 'Skipped (Local Mode)'
    }
    
    $dirty = if (GitC -Path $r -ArgList @('status','--porcelain')) { 'DIRTY' } else { 'Clean' }
    
    $row = [pscustomobject]@{ 
        RepoRoot=$r
        Branch=$branch
        Origin=$origin
        Upstream=$upstream
        Ahead=$ahead
        Behind=$behind
        Pushed=$pushed
        Dirty=$dirty
    }
    
    if ($ShowNested) {
        $parentRepo = Test-IsNestedRepo -RepoPath $r -AllRepoPaths $repoRoots
        $row | Add-Member -NotePropertyName 'Nested' -NotePropertyValue $(if ($parentRepo) { "YES (in $parentRepo)" } else { 'NO' })
    }
    
    $rows += $row
}

if (-not $QuietMode) { Write-Progress -Activity "Analyzing repositories" -Completed }

# Output results
Write-LogOutput "`n=== Repository Status Report ===" -ForegroundColor Green

# Create both console output and log-friendly format
$consoleTable = $rows | Sort-Object RepoRoot | Format-Table -AutoSize | Out-String
Write-Host $consoleTable

# Add structured output to log
if ($LogFile) {
    $script:logOutput += "Repository Status Report:"
    $script:logOutput += "======================="
    foreach ($row in ($rows | Sort-Object RepoRoot)) {
        $script:logOutput += "Repo: $($row.RepoRoot)"
        $script:logOutput += "  Branch: $($row.Branch)"
        $script:logOutput += "  Origin: $($row.Origin)"
        $script:logOutput += "  Upstream: $($row.Upstream)"
        $script:logOutput += "  Ahead: $($row.Ahead), Behind: $($row.Behind)"
        $script:logOutput += "  Pushed: $($row.Pushed), Status: $($row.Dirty)"
        if ($ShowNested -and $row.Nested) {
            $script:logOutput += "  Nested: $($row.Nested)"
        }
        $script:logOutput += ""
    }
}

# Summary statistics
$totalRepos = $rows.Count
$dirtyRepos = ($rows | Where-Object { $_.Dirty -eq 'DIRTY' }).Count
$unpushedRepos = ($rows | Where-Object { $_.Pushed -eq 'NO' }).Count
$aheadRepos = ($rows | Where-Object { [int]$_.Ahead -gt 0 }).Count
$behindRepos = ($rows | Where-Object { [int]$_.Behind -gt 0 }).Count

Write-LogOutput "`n=== Summary ===" -ForegroundColor Yellow
Write-LogOutput "Total repositories: $totalRepos"
Write-LogOutput "Dirty (uncommitted changes): $dirtyRepos"
Write-LogOutput "Not pushed to origin: $unpushedRepos" 
Write-LogOutput "Ahead of upstream: $aheadRepos"
Write-LogOutput "Behind upstream: $behindRepos"

if ($ShowNested) {
    $nestedRepos = ($rows | Where-Object { $_.Nested -and $_.Nested -ne 'NO' }).Count
    Write-LogOutput "Nested repositories: $nestedRepos"
}

# Write log file
if ($LogFile) {
    try {
        $logContent = $logOutput -join "`n"
        if ($AppendLog -and (Test-Path $LogFile)) {
            Add-Content -Path $LogFile -Value $logContent -Encoding UTF8
        } else {
            Set-Content -Path $LogFile -Value $logContent -Encoding UTF8
        }
        Write-Host ("`nResults logged to: {0}" -f $LogFile) -ForegroundColor Green
    } catch {
        Write-Warning ("Failed to write log file {0}: {1}" -f $LogFile, $_.Exception.Message)
    }
}

# CSV export
if ($CsvOut) {
    try {
        $rows | Sort-Object RepoRoot | Export-Csv -Path $CsvOut -NoTypeInformation -Encoding UTF8
        Write-Host ("`nResults exported to: {0}" -f $CsvOut) -ForegroundColor Green
    } catch {
        Write-Warning ("Failed to export CSV to {0}: {1}" -f $CsvOut, $_.Exception.Message)
    }
}