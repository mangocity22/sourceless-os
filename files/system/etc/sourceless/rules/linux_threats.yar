import "elf"
import "math"

/*
    Rule 1: High Entropy & Obfuscated Executables
    Targets: UPX-corrupted headers, packed droppers, and encrypted payloads.
*/
rule Linux_Packed_High_Entropy_ELF {
    meta:
        description = "Detects packed, encrypted, or heavily obfuscated Linux ELF binaries"
        author = "Sourceless Security"
        severity = "High"
    condition:
        // Validate ELF magic bytes: 0x7F 'E' 'L' 'F'
        uint32(0) == 0x464c457f and
        (
            // Overall file entropy threshold indicating raw encrypted/compressed data
            math.entropy(0, filesize) > 7.35 or
            
            // Per-section inspection for anomalous high entropy
            for any section in elf.sections : (
                math.entropy(section.offset, section.size) > 7.45
            ) or

            // Detection of stripped, corrupt, or missing section headers frequently used by loaders
            (elf.number_of_sections == 0 and filesize > 10KB)
        )
}

/*
    Rule 2: Linux Ransomware Signatures & Behaviors
    Targets: Akira, LockBit Linux, RansomExx, and Babuk derivatives.
*/
rule Linux_Ransomware_Behavior {
    meta:
        description = "Detects ransomware indicators targeting Linux filesystems"
        author = "Sourceless Security"
        severity = "Critical"
    strings:
        // Cryptographic and hashing primitives
        $crypto_1 = "AES_cbc_encrypt" ascii
        $crypto_2 = "EVP_CipherInit" ascii
        $crypto_3 = "mbedtls_aes_crypt" ascii
        $crypto_4 = "crypto_box_easy" ascii
        $crypto_5 = "ChaCha20" ascii

        // Typical ransom note artifacts and extortion markers
        $note_1 = "All your files have been encrypted" ascii nocase
        $note_2 = "DECRYPT_FILES" ascii nocase
        $note_3 = "README_FOR_DECRYPT" ascii nocase
        $note_4 = "your personal decryption key" ascii nocase
        $note_5 = "bitcoin" ascii nocase
        $note_6 = "tor browser" ascii nocase
        $note_7 = ".onion" ascii nocase
    condition:
        // Must contain at least one encryption artifact combined with extortion indicators
        (any of ($crypto_*)) and (2 of ($note_*))
}

/*
    Rule 3: Interactive Reverse Shells and Base64 Pipes
    Targets: Malicious one-liners, stagers, and interactive C2 connections.
*/
rule Linux_Interactive_Reverse_Shell {
    meta:
        description = "Detects interactive reverse shell implementations and encoded droppers"
        author = "Sourceless Security"
        severity = "High"
    strings:
        // Direct bash TCP redirection
        $bash_tcp = /\/dev\/tcp\/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\/[0-9]{2,5}/ ascii
        $bash_exec = /exec\s+[0-9]*<>\s*\/dev\/tcp/ ascii

        // Obfuscated base64 payload piped into an interpreter
        $b64_pipe = /echo\s+[A-Za-z0-9+\/=]{24,}\s*\|\s*base64\s+-d\s*\|\s*(ba)?sh/ ascii

        // Standard Python and Perl one-liner payloads
        $py_shell = "import socket,subprocess,os;s=socket.socket" ascii
        $perl_shell = "use Socket;$i=\"" ascii
        $nc_shell = /nc(\.traditional)?\s+-[a-zA-Z0-9]*e\s+\/(bin|usr)\/(ba)?sh/ ascii
    condition:
        any of them
}

/*
    Rule 4: Persistence via Volatile and Temporary Paths
    Targets: Malware installing cron tasks or systemd units from volatile locations.
*/
rule Linux_Persistence_Volatile_Path {
    meta:
        description = "Detects cron jobs or service units executing from temporary paths"
        author = "Sourceless Security"
        severity = "Medium"
    strings:
        $cron_loc_1 = "/etc/cron." ascii
        $cron_loc_2 = "/var/spool/cron/" ascii
        $systemd_loc = "/etc/systemd/system/" ascii
        
        $bad_path_1 = "/tmp/" ascii
        $bad_path_2 = "/dev/shm/" ascii
        $bad_path_3 = "/var/tmp/" ascii
    condition:
        (any of ($cron_loc_*) or $systemd_loc) and (any of ($bad_path_*))
}

/*
    Rule 5: Dynamic Linker Hijacking (Userland Rootkits)
    Targets: Bedep, Azazel, and custom LD_PRELOAD hooking mechanisms.
*/
rule Linux_Rootkit_LD_Preload_Hijack {
    meta:
        description = "Detects library injection and dynamic linker hijacking attempts"
        author = "Sourceless Security"
        severity = "Critical"
    strings:
        $preload_env = "LD_PRELOAD" ascii
        $preload_file = "/etc/ld.so.preload" ascii
        $dlsym_hook = "dlsym(RTLD_NEXT" ascii
        $sys_hook_1 = "readdir" ascii
        $sys_hook_2 = "fopen" ascii
    condition:
        ($preload_file or $preload_env) and ($dlsym_hook or all of ($sys_hook_*))
}

/*
    Rule 6: Credential Harvesting via Process Memory Inspection
    Targets: Mimipenguin, Linikatz, and memory scanners harvesting sensitive tokens.
*/
rule Linux_Credential_Access_Proc_Mem {
    meta:
        description = "Detects credential dumping via direct inspection of process memory"
        author = "Sourceless Security"
        severity = "High"
    strings:
        $proc_mem = /\/proc\/[0-9*]+\/mem/ ascii
        $proc_maps = /\/proc\/[0-9*]+\/maps/ ascii
        $pstate = "ptrace(PTRACE_ATTACH" ascii
        $gnome_keyring = "gnome-keyring-daemon" ascii
        $ssh_agent = "ssh-agent" ascii
    condition:
        ($proc_mem and $proc_maps) or ($pstate and ($gnome_keyring or $ssh_agent))
}

/*
    Rule 7: INC Ransomware & Linux/ESXi Storage Targeters
    Targets: INC Ransomware, LockBit ESXi, Babuk, and hypervisor-targeted wipers.
*/
rule Linux_Ransomware_INC_ESXi {
    meta:
        description = "Detects INC Ransomware variants targeting Linux and VMware ESXi environments"
        author = "Sourceless Security"
        severity = "Critical"
    strings:
        // INC specific ransom note markers
        $inc_note = "INC-README.txt" ascii
        $inc_motd = "Replace default Message of the day by ransom note" ascii
        
        // ESXi disruption primitives
        $esxi_stop = "while stopping ESXi machines" ascii
        $esxi_snap = "while removing ESXi snapshots" ascii
        $esxi_flag = "esxi-snapDelete snapshots" ascii
        
        // Core execution parameters
        $enc_mode = "Encryption mode (fast, medium, slow)" ascii
        $enc_daemon = "Detach an application from SSH connection, so you can close it and continue encryption" ascii
    condition:
        $inc_note or 
        (2 of ($esxi_*)) or 
        ($enc_mode and any of ($inc_motd, $enc_daemon))
}

rule Linux_Malformed_AntiAnalysis_ELF {
    meta:
        description = "Detects malformed or truncated ELF binaries crafted to bypass dynamic analysis"
        author = "Sourceless Security"
        severity = "High"
    condition:
        // ELF Magic bytes
        uint32(0) == 0x464c457f and
        (
            // 64-bit ELF: section header offset (offset 0x28) points beyond file size
            (uint8(4) == 2 and uint32(0x28) > filesize) or
            // 32-bit ELF: section header offset (offset 0x20) points beyond file size
            (uint8(4) == 1 and uint32(0x20) > filesize)
        )
}