$siteName = "kohv.nolvak.local"
$caName = "NOLVAK-AD-CA"

Write-Host "=== Sertifikaadi kontroll ===" -ForegroundColor Cyan

# Kontroll 1: serveri sertifikaat Personal store all
# Lisatud 'Sort-Object' ja 'Select-Object', et vältida massiivi viga (System.Object[])
$cert = Get-ChildItem Cert:\LocalMachine\My |
    Where-Object { $_.Subject -like "*CN=$siteName*" } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1

if ($cert) {
    Write-Host "OK - Serveri sertifikaat leitud" -ForegroundColor Green
    Write-Host "Subject: $($cert.Subject)"
    Write-Host "Issuer : $($cert.Issuer)"
    Write-Host "Valid  : $($cert.NotBefore) kuni $($cert.NotAfter)"
} else {
    Write-Host "VIGA - Serveri sertifikaati ei leitud LocalMachine\My hoidlast" -ForegroundColor Red
}

Write-Host "`n=== CA usaldus kontroll ===" -ForegroundColor Cyan

# Kontroll 2: Trusted Root store
$rootCA = Get-ChildItem Cert:\LocalMachine\Root |
    Where-Object { $_.Subject -like "*CN=$caName*" } |
    Select-Object -First 1

if ($rootCA) {
    Write-Host "OK - Root CA on Trusted Root hoidlas" -ForegroundColor Green
    Write-Host "CA: $($rootCA.Subject)"
} else {
    Write-Host "VIGA - Root CA puudub Trusted Root hoidlast" -ForegroundColor Red
}

Write-Host "`n=== Sertifikaadi ahela kontroll ===" -ForegroundColor Cyan

if ($cert) {
    $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
    # Kuna $cert on nüüd kindlasti üks objekt, siis .Build($cert) töötab veatult
    $chain.Build($cert) | Out-Null

    if ($chain.ChainStatus.Count -eq 0) {
        Write-Host "OK - Sertifikaadi ahel on usaldatud" -ForegroundColor Green
    } else {
        Write-Host "VIGA - Sertifikaadi ahel ei ole korras" -ForegroundColor Red
        $chain.ChainStatus | ForEach-Object {
            Write-Host $_.Status
            Write-Host $_.StatusInformation
        }
    }
}

Write-Host "`n=== DNS kontroll ===" -ForegroundColor Cyan

try {
    $dns = Resolve-DnsName $siteName -ErrorAction Stop
    Write-Host "OK - DNS lahendab nime" -ForegroundColor Green
    $dns | Format-Table Name, IPAddress -AutoSize
}
catch {
    Write-Host "VIGA - DNS nimi ei lahendu" -ForegroundColor Red
}

Write-Host "`nKontroll lõpetatud."
