#!/bin/bash
echo "=== Diagnostic PBS Backup ==="

# Test de la clé
echo "1. Test de la clé de chiffrement..."
if proxmox-backup-client key show /etc/pbs/pbs-encryption.key 2>/dev/null; then
    echo "✅ Clé sans mot de passe trouvée"
else
    echo "⚠️ Clé avec mot de passe ou introuvable"
fi

# Test webhook Discord
echo "2. Test webhook Discord..."
DISCORD_WEBHOOK_URL="votre_url"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    -H "Content-Type: application/json" \
    -X POST \
    -d '{"content":"🧪 Test depuis '$(hostname)'"}' \
    "$DISCORD_WEBHOOK_URL")

http_code=$(echo "$response" | tail -n1 | cut -d: -f2)
if [[ "$http_code" == "204" ]] || [[ "$http_code" == "200" ]]; then
    echo "✅ Webhook fonctionne"
else
    echo "❌ Webhook ne fonctionne pas (HTTP $http_code)"
fi

echo "=== Fin du diagnostic ==="
