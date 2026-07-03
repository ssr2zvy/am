# amcupa - amc sync toggle (no mount - uses podman cp)
# Toggles background sync between host and container vin/ directory
# Usage: amcupa [status]
#   (no args)  Toggle sync
#   status     Show sync status

amcupa() {
    sh "$amc_loc/amupa/gu.sh" "$@"
}
