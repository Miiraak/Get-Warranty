function Format-WarrantyTable {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    $WarrantyObject
  )

  $model = $WarrantyObject.model
  if (-not $model) { $model = "" }

  Write-Output ("{0}  {1}  SN={2}" -f $WarrantyObject.manufacturer, $model, $WarrantyObject.serial)
  Write-Output ("CheckedAt(UTC): {0}  Source: {1}" -f $WarrantyObject.checked_at, $WarrantyObject.source)
  Write-Output ""

  if ($WarrantyObject.warranties -and $WarrantyObject.warranties.Count -gt 0) {
    $WarrantyObject.warranties |
      Select-Object name, start, end, status, notes |
      Format-Table -AutoSize | Out-String | Write-Output
  } else {
    Write-Output "No warranty entries returned."
  }
}