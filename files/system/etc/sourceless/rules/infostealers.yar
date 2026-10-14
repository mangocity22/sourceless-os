/*
   Sourceless-OS Autonomous Threat Signatures
   Target: Infostealers, Droppers, Cryptominers, Reverse Shells, and Standard Test Files
*/

rule AntiVirus_EICAR_Test_File {
    meta:
        description = "Standard EICAR antivirus test payload"
    strings:
        $eicar = "X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*" ascii
    condition:
        $eicar
}

rule Linux_Credential_Stealer {
    meta:
        description = "Detects credential harvesting and exfiltration attempts"
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
        description = "Detects pipe-to-shell downloaders"
    strings:
        $pipe_sh = /(curl|wget)[^\n]{1,120}\|[ ]*(bash|sh|python)/ ascii
        $base64_pipe = /base64 -d[^\n]{1,60}\|[ ]*(bash|sh)/ ascii
    condition:
        any of them
}

rule Linux_Cryptominer_Payload {
    meta:
        description = "Detects Monero/XMRig miners and Stratum mining pools"
    strings:
        $stratum1 = "stratum+tcp://" ascii nocase
        $stratum2 = "stratum+ssl://" ascii nocase
        $pool1 = "pool.minexmr.com" ascii nocase
        $pool2 = "pool.supportxmr.com" ascii nocase
        $pool3 = "xmr.nanopool.org" ascii nocase
        $xmrig_bin = "xmrig" ascii nocase
        $donate_flag = "--donate-level=" ascii
    condition:
        any of ($stratum1, $stratum2, $pool1, $pool2, $pool3) or ($xmrig_bin and $donate_flag)
}

rule Linux_Persistence_Mechanism {
    meta:
        description = "Detects silent cron persistence targeting volatile or temporary storage"
    strings:
        $cron_tmp = /\/etc\/cron\.[a-z]+\/.*(\/tmp|\/dev\/shm)/ ascii
        $cron_spool = /\/var\/spool\/cron\/.*(\/tmp|\/dev\/shm)/ ascii
    condition:
        any of them
}

rule Reverse_Shell_Payload {
    meta:
        description = "Detects generic interactive reverse shells"
    strings:
        $bash_tcp = /\/dev\/tcp\/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\/[0-9]{2,5}/ ascii
        $nc_exec = /nc[ ]+(-e|\/bin\/(ba)?sh)[ ]+/ ascii
    condition:
        any of them
}

rule Linux_Botnet_Mirai_Family {
    meta:
        description = "Detects Mirai, Gafgyt and Iranbot IoT DDoS variants"
    strings:
        $telnet = "telnet" ascii nocase
        $busybox = "busybox" ascii nocase
        $shutdown_msg = "Cannot send after socket shutdown" ascii
        $iranbot = "Iranbot init" ascii
    condition:
        $iranbot or ($shutdown_msg and any of ($telnet, $busybox))
}

rule Linux_Persistence_Mechanism {
    meta:
        description = "Detects silent cron persistence targeting volatile or temporary storage"
    strings:
        $cron_tmp = /\/etc\/cron\.[a-z]+\/.{1,120}(\/tmp|\/dev\/shm)/ ascii
        $cron_spool = /\/var\/spool\/cron\/.{1,120}(\/tmp|\/dev\/shm)/ ascii
    condition:
        any of them
}