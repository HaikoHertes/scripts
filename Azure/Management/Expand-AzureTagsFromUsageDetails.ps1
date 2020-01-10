# Script to expand tags from the usage details CSV provided by Azure / Microsoft
# to filter usage by tags; also converts some numbers to local format
# Download CSV file by hand first!


# This is needed for the FileOpen Dialog	
Add-Type -AssemblyName System.Windows.Forms
$FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ 
    InitialDirectory = [Environment]::GetFolderPath('Desktop') 
    Filter = 'CSV-Files (*.csv)|*.csv'
}
$null = $FileBrowser.ShowDialog() # Just to open the dialog

If($FileBrowser.FileName -eq "")
{
    Write-Verbose "No file selected - aborting."
    Break    
}

$CSV = Import-Csv $FileBrowser.FileName -Delimiter ","

for ($i=0; $i -lt $CSV.length; $i++) 
{
    # Showing progress
    Write-Progress -Activity "Expanding in Progress..." -Status "$([math]::truncate($i / $($CSV.length) * 100))% complete..." -PercentComplete $($i / $($CSV.length) * 100)
    
    # Converting dates and numbers to local format
    $CSV[$i].Date = [datetime]::ParseExact( $CSV[$i].Date, 'MM/dd/yyyy', $null).ToString("d")
    $CSV[$i].BillingPeriodStartDate = [datetime]::ParseExact( $CSV[$i].BillingPeriodStartDate, 'MM/dd/yyyy', $null).ToString("d")
    $CSV[$i].BillingPeriodEndDate = [datetime]::ParseExact( $CSV[$i].BillingPeriodEndDate, 'MM/dd/yyyy', $null).ToString("d")
    $CSV[$i].Quantity = [float]$CSV[$i].Quantity
    $CSV[$i].EffectivePrice = [float]$CSV[$i].EffectivePrice
    $CSV[$i].Cost = [float]$CSV[$i].Cost
    $CSV[$i].UnitPrice = [float]$CSV[$i].UnitPrice


    # Expand Tags
    $Tags = "{ $($CSV[$i].Tags) }" | ConvertFrom-Json # We need to add some brackets here...
    if ($Tags -ne $null) {
         $Tags.PSObject.Properties | ForEach { 
            $TagName = "Tag-$($_.Name)" 
            Add-Member -InputObject $CSV[$i] $TagName $_.Value 
            # Adding the heading - what a rhyme (; ...
            if ($CSV[0].PSObject.Properties[$TagName] -eq $null) {
                Add-Member -InputObject $CSV[0] $TagName $null -Force
            }
        }
    }

}

# Saving as Excel-readable CSV
$CSV | Export-Csv "$([System.IO.Path]::GetDirectoryName($FileBrowser.FileName))\$([io.path]::GetFileNameWithoutExtension($FileBrowser.FileName))_expanded.csv" -NoTypeInformation -Delimiter ";"
