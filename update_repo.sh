#!/bin/bash
# update_repo.sh — rebuild the dingoo Kodi repo after dropping in updated addon zips.
#
# Usage:
#   1. Replace the root zip(s) (plugin.video.fenlight.zip, script.module.cocoscrapers.zip,
#      script.fentastic.helper.zip, skin.fentastic.zip) with the new versions.
#   2. Run: ./update_repo.sh
#   3. If Fen Light was updated, edit packages/fenlightam_changes when prompted.
#
# The script then:
#   - strips macOS junk (.DS_Store, __MACOSX) from each zip
#   - copies versioned zips into zips/<id>/<id>-<version>.zip (old versions are kept)
#   - for Fen Light: updates packages/ (versioned zip + fenlightam_version) for the in-app updater
#   - regenerates addons.xml + addons.xml.md5
#   - offers to commit and push

set -euo pipefail
cd "$(dirname "$0")"

ADDONS=(plugin.video.fenlight script.module.cocoscrapers script.fentastic.helper skin.fentastic repository.dingoo)
CHANGED=0

addon_version() { # addon_version <id> -> version from the zip's addon.xml
	unzip -p "$1.zip" "$1/addon.xml" | xmllint --xpath 'string(/addon/@version)' -
}

echo "== Cleaning and versioning zips =="
for id in "${ADDONS[@]}"; do
	if [ ! -f "$id.zip" ]; then
		echo "  !! $id.zip missing at repo root — skipping"
		continue
	fi
	# strip macOS junk in place (zip -d fails when nothing matches; that's fine)
	zip -q -d "$id.zip" "*.DS_Store" "__MACOSX/*" >/dev/null 2>&1 || true
	version=$(addon_version "$id")
	if [ -z "$version" ]; then
		echo "  !! could not read version from $id.zip — skipping"
		continue
	fi
	dest="zips/$id/$id-$version.zip"
	mkdir -p "zips/$id"
	if [ ! -f "$dest" ] || ! cmp -s "$id.zip" "$dest"; then
		cp "$id.zip" "$dest"
		echo "  ++ $dest"
		CHANGED=1
	else
		echo "  ok $id $version (unchanged)"
	fi
done

echo "== Fen Light updater channel (packages/) =="
if [ -f plugin.video.fenlight.zip ]; then
	fl_version=$(addon_version plugin.video.fenlight)
	mkdir -p packages
	cp plugin.video.fenlight.zip "packages/plugin.video.fenlight-$fl_version.zip"
	old_version=$(cat packages/fenlightam_version 2>/dev/null || echo "")
	printf '%s' "$fl_version" > packages/fenlightam_version
	if [ "$fl_version" != "$old_version" ]; then
		echo "  ++ Fen Light $old_version -> $fl_version"
		echo ""
		echo "  >> EDIT packages/fenlightam_changes NOW with the $fl_version changelog <<"
		echo "     (users see it in Fen Light's update prompt)"
		read -r -p "  Press Enter once the changelog is saved..."
		CHANGED=1
	else
		echo "  ok Fen Light $fl_version (unchanged)"
	fi
fi

echo "== Regenerating addons.xml + md5 =="
{
	echo '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
	echo '<addons>'
	for id in "${ADDONS[@]}"; do
		[ -f "$id.zip" ] && unzip -p "$id.zip" "$id/addon.xml" | sed '/<?xml/d'
	done
	echo '</addons>'
} > addons.xml
xmllint --noout addons.xml
md5 -q addons.xml | tr -d '\n' > addons.xml.md5
echo "  md5: $(cat addons.xml.md5)"

if git diff --quiet && git diff --cached --quiet && [ -z "$(git status --porcelain)" ]; then
	echo "== Nothing changed — repo already up to date =="
	exit 0
fi

echo "== Pending changes =="
git status --short
read -r -p "Commit and push to GitHub? [y/N] " answer
if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
	git add -A
	git commit -m "Update addons via update_repo.sh"
	git push origin main
	echo "== Pushed. GitHub Pages redeploys in ~1 minute. =="
else
	echo "== Left uncommitted. Run 'git add -A && git commit && git push' when ready. =="
fi
