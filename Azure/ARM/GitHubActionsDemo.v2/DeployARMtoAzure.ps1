# Find all template files in naming scheme XYZ.json
# For each template file, a parameters file with naming format XYZ.parameters.json is expected
$templates = Get-ChildItem -Path "arm\" -Filter "*.json" -File -Recurse | Where Name -notlike "*parameters.json"
Write-Host "Found $($templates.Count) JSON templates..."

# Iterate through all Templates, ordered by filename
ForEach($template in ($templates | Sort-Object -Property BaseName))
{   
    Write-Host "Using $($template.Name)..."
    # Create RG if not allready existing
    $RGName = Split-Path $template.DirectoryName -Leaf
    $Location = Get-Content -Path "$($template.DirectoryName)\location.txt"
    $Tags = @{}
    # Load Tags if tags.txt does exist
    If(Test-Path -Path "$($template.DirectoryName)\tags.txt")
    {
        $Tags = Get-Content "$($template.DirectoryName)\tags.txt" -Raw | ConvertFrom-StringData
    }

    Get-AzResourceGroup -Name $RGName -ErrorVariable notPresent -ErrorAction SilentlyContinue
    if ($notPresent)
    {
        # ResourceGroup doesn't exist
        Write-Host "ResourceGroup $RGName does not exist..."
        New-AzResourceGroup `
            -Name $RGName `
            -Location $Location `
            -Tags $Tags
        Write-Host "ResourceGroup $RGName created..."
    }
    else
    {
        # ResourceGroup exist
        Write-Host "ResourceGroup $RGName does exist..."
    }
    Write-Host "Location will be $Location"    # Starting the deployment    Write-Host "Deploying $($template.Name)..."    New-AzResourceGroupDeployment `            -ResourceGroupName $RGName `            -TemplateFile $template.FullName `            -TemplateParameterFile "$($template.DirectoryName)\$($template.BaseName).parameters.json" `
            -Tag $tags
}