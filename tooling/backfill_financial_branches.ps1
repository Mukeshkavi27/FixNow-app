param(
  [Parameter(Mandatory = $true)][string]$Email,
  [Parameter(Mandatory = $true)][string]$Password
)

$ErrorActionPreference = 'Stop'
$projectId = 'fixnow-a6515'
$apiKey = 'AIzaSyDeO15iDL-kJ-FOHcKRApj-vb-i5-rjIv0'
$databaseBase = "https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents"

$signInBody = @{
  email = $Email
  password = $Password
  returnSecureToken = $true
} | ConvertTo-Json
$session = Invoke-RestMethod `
  -Method Post `
  -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey" `
  -ContentType 'application/json' `
  -Body $signInBody
$headers = @{ Authorization = "Bearer $($session.idToken)" }

function Get-Collection([string]$collection) {
  try {
    $response = Invoke-RestMethod `
      -Method Get `
      -Uri "$databaseBase/${collection}?pageSize=300" `
      -Headers $headers
  } catch {
    $stream = $_.Exception.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($stream)
    throw "Firestore read failed for $collection`: $($reader.ReadToEnd())"
  }
  if ($null -eq $response.documents) { return @() }
  return @($response.documents)
}

function Get-StringField($document, [string]$field) {
  $value = $document.fields.$field
  if ($null -eq $value) { return $null }
  return $value.stringValue
}

function Update-StringFields(
  [string]$documentName,
  [hashtable]$values
) {
  $fields = @{}
  $masks = @()
  foreach ($entry in $values.GetEnumerator()) {
    if ([string]::IsNullOrWhiteSpace([string]$entry.Value)) { continue }
    $fields[$entry.Key] = @{ stringValue = [string]$entry.Value }
    $masks += "updateMask.fieldPaths=$([uri]::EscapeDataString($entry.Key))"
  }
  if ($fields.Count -eq 0) { return }
  $documentPath = $documentName.Substring($documentName.IndexOf('/documents/') + 11)
  $query = $masks -join '&'
  try {
    Invoke-RestMethod `
      -Method Patch `
      -Uri "$databaseBase/$documentPath`?$query" `
      -Headers $headers `
      -ContentType 'application/json' `
      -Body (@{ fields = $fields } | ConvertTo-Json -Depth 6) | Out-Null
  } catch {
    $stream = $_.Exception.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($stream)
    throw "Firestore update failed for $documentPath`: $($reader.ReadToEnd())"
  }
}

$users = Get-Collection 'users'
$branches = Get-Collection 'branches'
$bookings = Get-Collection 'bookings'
$bills = Get-Collection 'bills'
$incentives = Get-Collection 'technician_incentives'

$branchNames = @{}
foreach ($branch in $branches) {
  $branchId = $branch.name.Split('/')[-1]
  $branchNames[$branchId] = Get-StringField $branch 'name'
}

$technicians = @{}
$updatedTechnicians = 0
foreach ($user in $users) {
  if ((Get-StringField $user 'role') -ne 'technician') { continue }
  $uid = $user.name.Split('/')[-1]
  $currentBranchId = Get-StringField $user 'branchId'
  $currentBranchName = Get-StringField $user 'branchName'
  $nativeBranchId = Get-StringField $user 'nativeBranchId'
  $nativeBranchName = Get-StringField $user 'nativeBranchName'
  if ([string]::IsNullOrWhiteSpace($nativeBranchId)) {
    $nativeBranchId = $currentBranchId
    $nativeBranchName = if (-not [string]::IsNullOrWhiteSpace($currentBranchName)) {
      $currentBranchName
    } else {
      $branchNames[$currentBranchId]
    }
    Update-StringFields $user.name @{
      nativeBranchId = $nativeBranchId
      nativeBranchName = $nativeBranchName
    }
    $updatedTechnicians++
  }
  $technicians[$uid] = @{
    currentBranchId = $currentBranchId
    nativeBranchId = $nativeBranchId
  }
}

$bookingBranches = @{}
foreach ($booking in $bookings) {
  $bookingBranches[$booking.name.Split('/')[-1]] = Get-StringField $booking 'branchId'
}

$updatedBills = 0
foreach ($bill in $bills) {
  $bookingId = Get-StringField $bill 'bookingId'
  $technicianId = Get-StringField $bill 'technicianId'
  $serviceBranchId = Get-StringField $bill 'branchId'
  if ([string]::IsNullOrWhiteSpace($serviceBranchId)) {
    $serviceBranchId = $bookingBranches[$bookingId]
  }
  $revenueBranchId = Get-StringField $bill 'revenueBranchId'
  if ([string]::IsNullOrWhiteSpace($revenueBranchId)) {
    $technician = $technicians[$technicianId]
    $revenueBranchId = if ($null -ne $technician) {
      $technician.nativeBranchId
    } else {
      $serviceBranchId
    }
  }
  $changes = @{}
  if ([string]::IsNullOrWhiteSpace((Get-StringField $bill 'branchId')) `
      -and -not [string]::IsNullOrWhiteSpace($serviceBranchId)) {
    $changes.branchId = $serviceBranchId
  }
  if ([string]::IsNullOrWhiteSpace((Get-StringField $bill 'revenueBranchId')) `
      -and -not [string]::IsNullOrWhiteSpace($revenueBranchId)) {
    $changes.revenueBranchId = $revenueBranchId
  }
  if ($changes.Count -gt 0) {
    Update-StringFields $bill.name $changes
    $updatedBills++
  }
}

$updatedIncentives = 0
foreach ($incentive in $incentives) {
  if (-not [string]::IsNullOrWhiteSpace(
      (Get-StringField $incentive 'revenueBranchId'))) {
    continue
  }
  $technicianId = Get-StringField $incentive 'technicianId'
  $technician = $technicians[$technicianId]
  $revenueBranchId = if ($null -ne $technician) {
    $technician.nativeBranchId
  } else {
    Get-StringField $incentive 'branchId'
  }
  Update-StringFields $incentive.name @{
    revenueBranchId = $revenueBranchId
  }
  $updatedIncentives++
}

[pscustomobject]@{
  techniciansScanned = $technicians.Count
  techniciansBackfilled = $updatedTechnicians
  billsScanned = $bills.Count
  billsBackfilled = $updatedBills
  incentivesScanned = $incentives.Count
  incentivesBackfilled = $updatedIncentives
} | ConvertTo-Json
