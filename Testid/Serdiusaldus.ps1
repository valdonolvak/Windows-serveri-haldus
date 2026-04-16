$siteName = "kohv.nolvak.local"
$caName = "NOLVAK-AD-CA"
$expectedIP = "10.0.10.10"

Write-Host "=== KLIENDI KONTROLL: $siteName ===" -ForegroundColor Cyan

# 1. Kontroll: Kas Root CA on kliendi arvutis usaldatud?
Write-Host "`n[1/3] Root CA kontroll..." -NoNewline
$rootCert = Get-ChildItem Cert:\LocalMachine\Root, Cert:\CurrentUser\Root | 
            Where-Object { $_.Subject -like "*CN=$caName*" } | Select-Object -First 1

if ($rootCert) {
    Write-Host " OK" -ForegroundColor Green
    Write-Host "    Leitud: $($rootCert.Subject)"
} else {
    Write-Host " VIGA" -ForegroundColor Red
    Write-Host "    KLIENDI arvuti ei usalda $caName sertifikaati!" -ForegroundColor Yellow
}

# 2. Kontroll: DNS lahendamine kliendi juurest
Write-Host "`n[2/3] DNS kontroll..." -NoNewline
try {
    $dns = Resolve-DnsName $siteName -ErrorAction Stop
    $resolvedIP = $dns.IPAddress | Select-Object -First 1
    if ($resolvedIP -eq $expectedIP) {
        Write-Host " OK ($resolvedIP)" -ForegroundColor Green
    } else {
        Write-Host " HOIATUS" -ForegroundColor Yellow
        Write-Host "    Nimi lahendub aadressile $resolvedIP, ootasime $expectedIP"
    }
} catch {
    Write-Host " VIGA" -ForegroundColor Red
    Write-Host "    Kliendi arvuti ei oska nime $siteName lahendada!" -ForegroundColor Yellow
}

# 3. Kontroll: Veebiühendus ja sertifikaadi nimi (SAN kontroll)
Write-Host "`n[3/3] Veebiühenduse ja nime klapi kontroll..." -NoNewline
try {
    $uri = "https://$siteName"
    $webRequest = [Net.HttpWebRequest]::Create($uri)
    $webRequest.Timeout = 5000
    # See rida ignoreerib vigu, et me saaksime sertifikaati vaadata isegi kui see on "ebaturvaline"
    $webRequest.ServerCertificateValidationCallback = {$true}
    $response = $webRequest.GetResponse()
    $serverCert = $webRequest.ServicePoint.Certificate
    $cert2 = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($serverCert)
    
    if ($cert2.Subject -like "*CN=$siteName*") {
        Write-Host " OK" -ForegroundColor Green
        Write-Host "    Sertifikaadi nimi klapib aadressiga."
    } else {
        Write-Host " VIGA" -ForegroundColor Red
        Write-Host "    Sertifikaadi Subject ($($cert2.Subject)) ei kattu aadressiga $siteName!" -ForegroundColor Yellow
    }
    $response.Close()
} catch {
    Write-Host " VIGA" -ForegroundColor Red
    Write-Host "    Ei saanud serveriga HTTPS ühendust: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "`n=== Kontroll lõpetatud ===" -ForegroundColor Cyan
