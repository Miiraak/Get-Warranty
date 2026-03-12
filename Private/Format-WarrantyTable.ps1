function Format-WarrantyTable {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    $WarrantyObject
  )

  $mfr    = if ($WarrantyObject.manufacturer) { $WarrantyObject.manufacturer } else { "?" }
  $model  = if ($WarrantyObject.model)        { $WarrantyObject.model }        else { "" }
  $serial = if ($WarrantyObject.serial)       { $WarrantyObject.serial }       else { "N/A" }

  Write-Output ("{0}  {1}  SN={2}" -f $mfr, $model, $serial)
  Write-Output ("CheckedAt(UTC): {0}  Source: {1}" -f $WarrantyObject.checked_at, $WarrantyObject.source)
  Write-Output ""

  if ($WarrantyObject.warranties -and @($WarrantyObject.warranties).Count -gt 0) {
    $WarrantyObject.warranties |
      Select-Object name, start, end, status, notes |
      Format-Table -AutoSize | Out-String | Write-Output
  } else {
    Write-Output "No warranty entries returned."
  }
}