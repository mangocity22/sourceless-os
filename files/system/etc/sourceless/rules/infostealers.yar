rule Linux_Infostealer_Generic {
    meta:
        description = "Detects credential harvesting and exfiltration scripts/binaries"
        author = "Sourceless Security"
    strings:
        $discord = "discord.com/api/webhooks" ascii nocase
        $telegram = "api.telegram.org/bot" ascii nocase
        $ssh_harvest = ".ssh/id_rsa" ascii nocase
        $chrome_creds = "Login Data" ascii nocase
        $keyring = "keyrings" ascii nocase
        $wallet_metamask = "nkbihfbeogaeaoehlefnkodbefgpgknn" ascii nocase
    condition:
        any of ($discord, $telegram) and any of ($ssh_harvest, $chrome_creds, $keyring, $wallet_metamask)
}

rule Malicious_OneLiner_Dropper {
    meta:
        description = "Detects hidden curl/wget execution one-liners"
    strings:
        $pipe_bash = /(curl|wget)[^\n]{1,120}\|[ ]*(bash|sh|python)/ ascii
        $base64_exec = /base64 -d[^\n]{1,60}\|[ ]*(bash|sh)/ ascii
    condition:
        any of them
}