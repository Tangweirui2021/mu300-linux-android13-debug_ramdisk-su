# Host-side helpers for the local su-fallback variants; sourcing this file runs no device commands.
find_device_su() {
    SU=
    MU300_SU=; export MU300_SU
    for _su_candidate in su /debug_ramdisk/su /sbin/su /system/xbin/su /system/bin/su; do
        if _su_uid=$(adb shell "$_su_candidate -c 'id -u'" </dev/null 2>/dev/null); then
            _su_uid=$(printf '%s' "$_su_uid" | tr -d '\r')
            if [ "$_su_uid" = 0 ]; then
                SU=$_su_candidate
                MU300_SU=$SU; export MU300_SU # inherited by the vendor/GPU extractors
                return 0
            fi
        fi
    done
    return 1
}

wait_android_root() { # [attempts [delay_seconds [message]]]
    SU=
    MU300_SU=; export MU300_SU
    _su_attempts=${1:-60}
    _su_delay=${2:-2}
    _su_message=${3-'waiting for Android to finish starting and root access'}
    _su_try=0
    while [ "$_su_try" -lt "$_su_attempts" ]; do
        # getprop needs no root. Retry every candidate after boot, including a late Magisk daemon.
        if _su_boot=$(adb shell getprop sys.boot_completed </dev/null 2>/dev/null) &&
                [ "$(printf '%s' "$_su_boot" | tr -d '\r')" = 1 ] && find_device_su; then
            return 0
        fi
        if [ "$_su_try" = 0 ] && [ -n "$_su_message" ]; then printf '  %s\n' "$_su_message" >&2; fi
        _su_try=$((_su_try + 1))
        [ "$_su_try" -ge "$_su_attempts" ] || sleep "$_su_delay"
    done
    return 1
}
