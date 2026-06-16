<#
Google Maps Lead Scraper
========================
Drives a real Chrome browser via Selenium to search Google Maps for each
business category in each city/state, scrolls the results feed to load
every listing, and extracts Name / Address / Phone / Website / Rating.

REQUIREMENTS (run once):
  Install-Module Selenium -Scope CurrentUser -Force
  Download ChromeDriver matching your installed Chrome version from:
  https://googlechromelabs.github.io/chrome-for-testing/
  and place chromedriver.exe somewhere on your PATH (or set $chromeDriverDir below).

NOTES:
  - Google Maps caps a single search's results list (~100-120 listings).
    To actually get "everything" across 4 states, you must search per CITY,
    not just per state. This script ships with a starter list of major
    cities for GA/AL/NC/SC for each category - add more cities to widen coverage.
  - This automates a real browser visiting public Google Maps pages.
    Scraping Google Maps is against Google's Terms of Service - use at your
    own risk, keep request volume reasonable, and add delays (already built in)
    to reduce the chance of being rate-limited/blocked.
  - Re-run is safe: each category/city combo writes its own CSV, and a final
    step merges + dedupes everything into one master file.
#>

# ---------------------------------------------------------------------------
# CONFIG
# ---------------------------------------------------------------------------

$OutputDir = "$env:USERPROFILE\Desktop\MapsLeads"
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$Categories = @(
    "Civil Construction Company",
    "Electrician",
    "Trucking Company",
    "Heavy Equipment Dealer",
    "Diesel Truck Repair Shop",
    "Auto Mechanic Shop"
)

# Add/remove cities to control coverage. More cities = more total leads.
$Locations = @(
    # Georgia
    "Atlanta, GA","Augusta, GA","Columbus, GA","Macon, GA","Savannah, GA",
    "Athens, GA","Sandy Springs, GA","Roswell, GA","Albany, GA","Marietta, GA",
    "Valdosta, GA","Warner Robins, GA","Gainesville, GA","Brunswick, GA","Rome, GA",

    # Alabama
    "Birmingham, AL","Montgomery, AL","Mobile, AL","Huntsville, AL","Tuscaloosa, AL",
    "Hoover, AL","Dothan, AL","Auburn, AL","Decatur, AL","Florence, AL",
    "Gadsden, AL","Anniston, AL","Opelika, AL","Enterprise, AL",

    # North Carolina
    "Charlotte, NC","Raleigh, NC","Greensboro, NC","Durham, NC","Winston-Salem, NC",
    "Fayetteville, NC","Cary, NC","Wilmington, NC","High Point, NC","Asheville, NC",
    "Concord, NC","Gastonia, NC","Greenville, NC","Jacksonville, NC","Rocky Mount, NC",

    # South Carolina
    "Columbia, SC","Charleston, SC","North Charleston, SC","Greenville, SC","Rock Hill, SC",
    "Mount Pleasant, SC","Spartanburg, SC","Sumter, SC","Hilton Head Island, SC","Florence, SC",
    "Myrtle Beach, SC","Anderson, SC","Greenwood, SC","Aiken, SC"
)

$ScrollPasses   = 25      # how many times to scroll the results panel per search
$ScrollWaitSec  = 1.5     # pause between scrolls (let new listings load)
$BetweenSearchSec = 4     # pause between each category/city search

# ---------------------------------------------------------------------------
# SETUP SELENIUM
# ---------------------------------------------------------------------------

if (-not (Get-Module -ListAvailable -Name Selenium)) {
    Write-Host "Selenium module not found. Run: Install-Module Selenium -Scope CurrentUser -Force" -ForegroundColor Yellow
    exit 1
}
Import-Module Selenium

function New-MapsDriver {
    $chromeOptions = New-Object OpenQA.Selenium.Chrome.ChromeOptions
    $chromeOptions.AddArgument("--lang=en-US")
    $chromeOptions.AddArgument("--disable-blink-features=AutomationControlled")
    $chromeOptions.AddArgument("start-maximized")
    return New-Object OpenQA.Selenium.Chrome.ChromeDriver($chromeOptions)
}

function Get-MapsListings {
    param(
        [OpenQA.Selenium.Chrome.ChromeDriver]$Driver,
        [string]$Category,
        [string]$Location
    )

    $query = [System.Uri]::EscapeDataString("$Category in $Location")
    $url = "https://www.google.com/maps/search/$query"
    $Driver.Navigate().GoToUrl($url)
    Start-Sleep -Seconds 5

    # The scrollable results feed container
    $feedSelector = "div[role='feed']"
    $feed = $null
    try {
        $feed = $Driver.FindElementByCssSelector($feedSelector)
    } catch {
        Write-Host "  No results feed found for '$Category in $Location' (maybe zero results)." -ForegroundColor DarkYellow
        return @()
    }

    # Scroll the feed to force-load all listings
    for ($i = 0; $i -lt $ScrollPasses; $i++) {
        $Driver.ExecuteScript("arguments[0].scrollTop = arguments[0].scrollHeight", $feed) | Out-Null
        Start-Sleep -Seconds $ScrollWaitSec
    }

    $cards = $Driver.FindElementsByCssSelector("div[role='feed'] > div > div[jsaction]")
    $results = @()

    foreach ($card in $cards) {
        try {
            $name = $null
            try { $name = $card.FindElementByCssSelector(".fontHeadlineSmall").Text } catch {}
            if (-not $name) { continue }

            $rating = $null
            try { $rating = $card.FindElementByCssSelector("span.MW4etd").Text } catch {}

            $reviewCount = $null
            try { $reviewCount = $card.FindElementByCssSelector("span.UY7F9").Text -replace "[()]","" } catch {}

            $addressLine = $null
            $phoneLine = $null
            $infoLines = $card.FindElementsByCssSelector("div.W4Efsd > div.W4Efsd > span")
            foreach ($line in $infoLines) {
                $t = $line.Text
                if ($t -match "^\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}$") { $phoneLine = $t }
                elseif ($t -and -not $addressLine -and $t -notmatch "^\d+(\.\d+)?\s*\(") { $addressLine = $t }
            }

            $website = $null
            try { $website = $card.FindElementByCssSelector("a[data-value='Website']").GetAttribute("href") } catch {}

            $mapsLink = $null
            try { $mapsLink = $card.FindElementByCssSelector("a.hfpxzc").GetAttribute("href") } catch {}

            $results += [PSCustomObject]@{
                Category    = $Category
                SearchedIn  = $Location
                Name        = $name
                Rating      = $rating
                Reviews     = $reviewCount
                Address     = $addressLine
                Phone       = $phoneLine
                Website     = $website
                MapsLink    = $mapsLink
            }
        } catch {
            continue
        }
    }

    return $results
}

# ---------------------------------------------------------------------------
# MAIN LOOP
# ---------------------------------------------------------------------------

$driver = New-MapsDriver
$allResults = @()
$total = $Categories.Count * $Locations.Count
$done = 0

foreach ($category in $Categories) {
    foreach ($location in $Locations) {
        $done++
        Write-Host "[$done/$total] Scraping: $category - $location" -ForegroundColor Cyan

        $safeCat = ($category -replace '[^\w]+','_')
        $safeLoc = ($location -replace '[^\w]+','_')
        $fileName = Join-Path $OutputDir "$safeCat`_$safeLoc.csv"

        if (Test-Path $fileName) {
            Write-Host "  Already scraped, skipping." -ForegroundColor DarkGray
            continue
        }

        try {
            $rows = Get-MapsListings -Driver $driver -Category $category -Location $location
            if ($rows.Count -gt 0) {
                $rows | Export-Csv -Path $fileName -NoTypeInformation -Encoding UTF8
                $allResults += $rows
                Write-Host "  Found $($rows.Count) listings." -ForegroundColor Green
            } else {
                Write-Host "  Found 0 listings." -ForegroundColor DarkYellow
            }
        } catch {
            Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
        }

        Start-Sleep -Seconds $BetweenSearchSec
    }
}

$driver.Quit()

# ---------------------------------------------------------------------------
# MERGE + DEDUPE ALL RESULTS
# ---------------------------------------------------------------------------

Write-Host "Merging all per-search CSVs..." -ForegroundColor Cyan
$allCsvs = Get-ChildItem -Path $OutputDir -Filter "*.csv" | Where-Object { $_.Name -ne "ALL_LEADS_MASTER.csv" }
$merged = foreach ($csv in $allCsvs) { Import-Csv $csv.FullName }

$deduped = $merged | Sort-Object Name, Address | Group-Object Name, Address | ForEach-Object { $_.Group[0] }

$masterPath = Join-Path $OutputDir "ALL_LEADS_MASTER.csv"
$deduped | Export-Csv -Path $masterPath -NoTypeInformation -Encoding UTF8

Write-Host "Done. $($deduped.Count) unique leads written to: $masterPath" -ForegroundColor Green
