rule Linux_Credential_Stealer {
    meta:
        description = "Detects credentials harvesting and exfiltration attempts"
    strings:
        $exfil_discord = "discord.com/api/webhooks" ascii nocase
        $exfil_tg = "api.telegram.org/bot" ascii nocase
        $ssh = ".ssh/id_rsa" ascii nocase
        $keyring = "keyrings" ascii nocase
        $browser_creds = "Login Data" ascii nocase
        $wallet_meta = "nkbihfbeogaeaoehlefnkodbefgpgknn" ascii nocase
        $wallet_phantom = "bfnaelmomeimihpmgjnjophhpkkoljpa" ascii nocase
    condition:
        any of ($exfil_discord, $exfil_tg) and any of ($ssh, $keyring, $browser_creds, $wallet_meta, $wallet_phantom)
}

rule Malicious_Dropper_OneLiner {
    meta:
        description = "Detects blind pipe-to-shell scripts"
    strings:
        $pipe_sh = /(curl|wget)[^\n]{1,120}\|[ ]*(bash|sh|python)/ ascii
        $base64_pipe = /base64 -d[^\n]{1,60}\|[ ]*(bash|sh)/ ascii
    condition:
        any of them
}

rule Reverse_Shell_Payload {
    meta:
        description = "Detects interactive reverse shells"
    strings:
        $bash_tcp = /\/dev\/tcp\/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\/[0-9]{2,5}/ ascii
        $nc_exec = /nc[ ]+(-e|\/bin\/(ba)?sh)[ ]+/ ascii
    condition:
        any of them
}