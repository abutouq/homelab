# Telegram relay: api.telegram.org is blocked in Jordan (the ISP resets the TLS
# handshake), so the homelab bots send through this Worker instead. Their
# Telegram API base is set in helm/homelab-bots values (telegram.apiBase).
#
# Uses its own token, not the DNS-only one in secret/homelab/cloudflare: that
# one is copied onto the Teleport and Vault VMs, so it stays narrow.
# secret/homelab/cloudflare-workers holds:
#   api_token   Account > Workers Scripts > Edit, Zone (homebytes.space) >
#               Workers Routes > Edit
#   account_id  the Cloudflare account that owns homebytes.space

data "vault_generic_secret" "cloudflare_workers" {
  path = "secret/homelab/cloudflare-workers"
}

provider "cloudflare" {
  alias     = "workers"
  api_token = data.vault_generic_secret.cloudflare_workers.data["api_token"]
}

resource "cloudflare_workers_script" "telegram_relay" {
  provider           = cloudflare.workers
  account_id         = data.vault_generic_secret.cloudflare_workers.data["account_id"]
  script_name        = "telegram-relay"
  content            = file("${path.module}/telegram-relay/worker.js")
  main_module        = "worker.js"
  compatibility_date = "2026-11-01"

  # No placement block: provider 5.26 fails to serialize one ("failed to
  # serialize multipart http request", unknown computed placement.target), and
  # a fixed region is read-only there. The Worker runs at Cloudflare's location
  # nearest the caller; the getMe check in the output description shows
  # whether its request to Telegram still gets through from there.
}

resource "cloudflare_workers_custom_domain" "telegram_relay" {
  provider   = cloudflare.workers
  account_id = data.vault_generic_secret.cloudflare_workers.data["account_id"]
  zone_id    = local.cloudflare["zone_id"]
  hostname   = "notify-relay.homebytes.space"
  service    = cloudflare_workers_script.telegram_relay.script_name
}

output "telegram_relay_url" {
  description = "Check from the homelab: curl https://<this>/bot1:x/getMe should return Telegram's own 401 JSON, which proves the relay reaches Telegram."
  value       = "https://${cloudflare_workers_custom_domain.telegram_relay.hostname}"
}
