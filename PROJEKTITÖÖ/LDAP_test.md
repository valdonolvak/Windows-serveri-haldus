

---

### Täiendatud WordPressi LDAP sisselogimise kontroll

```powershell
# ========================================================
# WORDPRESS LDAP LOGIN TEST (HTTPS & HTTP TOETUSEGA)
# ========================================================

# 1. Käsk omapoolsete/valede sertifikaatide ignoreerimiseks (HTTPS jaoks)
[Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$TestPassword = "Passw0rd!"
$LoginSuccess = $false
$UsedProtocol = ""
$ErrorMessage = "Sisselogimine ebaõnnestus mõlema protokolliga"

# Proovime mõlemat protokolli, HTTPS eesjärjekorras
$Protocols = @("https", "http")

foreach ($Proto in $Protocols) {
    if ($LoginSuccess) { break } # Kui üks juba toimis, siis teist ei proovi

    try {
        $LoginUrl = "$($Proto)://$ProjectHost/wp-login.php"
        
        # Loome uue sessiooni iga katse jaoks
        $Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

        # 1. Ava sisselogimise leht (et saada küpsised/testcookie)
        Invoke-WebRequest -Uri $LoginUrl -WebSession $Session -TimeoutSec 5 -ErrorAction Stop | Out-Null

        # 2. Sisselogimise andmed
        $Body = @{
            log           = "pea.toimetaja@$DomainName"
            pwd           = $TestPassword
            "wp-submit"   = "Log In"
            redirect_to   = "$($Proto)://$ProjectHost/wp-admin/"
            testcookie    = "1"
        }

        # 3. Saada sisselogimise päring
        $Response = Invoke-WebRequest `
            -Uri $LoginUrl `
            -Method POST `
            -Body $Body `
            -WebSession $Session `
            -MaximumRedirection 10 `
            -TimeoutSec 10 `
            -ErrorAction Stop

        # 4. Kontrolli sisselogimise küpsist
        $LoggedInCookie = $Session.Cookies.GetCookies($LoginUrl) | Where-Object { 
            $_.Name -like "wordpress_logged_in*" 
        }

        if ($LoggedInCookie.Count -gt 0) {
            $LoginSuccess = $true
            $UsedProtocol = $Proto.ToUpper()
        }
    }
    catch {
        $ErrorMessage = "$($Proto.ToUpper()): $($_.Exception.Message)"
    }
}

# Tulemuse lisamine kontrolli
if ($LoginSuccess) {
    Add-Check `
        "WordPress LDAP Login" `
        "pea.toimetaja authenticates" `
        "SUCCESS ($UsedProtocol)" `
        $true `
        1 `
        1
}
else {
    Add-Check `
        "WordPress LDAP Login" `
        "pea.toimetaja authenticates" `
        "FAILED: $ErrorMessage" `
        $false `
        1 `
        1
}

```
