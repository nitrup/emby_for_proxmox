#!/bin/bash

# Fonction pour extraire la version installée localement
get_installed_version() {
    if dpkg -l | grep -q emby-server; then
        dpkg -s emby-server | grep '^Version:' | awk '{print $2}'
    else
        echo "none"
    fi
}

echo "🔍 Vérification de la dernière version (y compris bêta) d'Emby Server..."

# Récupérer la dernière release (même si bêta)
latest_version=$(curl -s https://api.github.com/repos/MediaBrowser/Emby.Releases/releases | grep "tag_name" | head -n 1 | cut -d '"' -f 4)

# Formater le nom du fichier
filename="emby-server-deb_${latest_version}_amd64.deb"
download_url="https://github.com/MediaBrowser/Emby.Releases/releases/download/${latest_version}/${filename}"

# Version installée localement
installed_version=$(get_installed_version)

echo "🖥️  Version installée : $installed_version"
echo "🌐 Dernière version disponible : $latest_version"

# Comparaison des versions (simple)
if [ "$installed_version" = "$latest_version" ]; then
    echo "✅ Vous avez déjà la dernière version."
    exit 0
fi

# Demander confirmation
read -p "⚠️  Souhaitez-vous mettre à jour vers la version $latest_version ? (y/n) : " answer
if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
    echo "❌ Mise à jour annulée."
    exit 0
fi

echo "⬇️ Téléchargement de $filename..."
wget --show-progress "$download_url" -O "$filename"

if [ $? -ne 0 ]; then
    echo "❌ Échec du téléchargement."
    exit 1
fi

echo "⚙️ Installation de Emby Server..."
sudo dpkg -i "$filename"

if [ $? -ne 0 ]; then
    echo "❌ Échec de l'installation."
    exit 1
fi

echo "🧹 Suppression du fichier téléchargé..."
rm -f "$filename"

echo "✅ Mise à jour vers la version $latest_version terminée avec succès !"
