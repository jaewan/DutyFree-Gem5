#!/usr/bin/env bash
# Build gem5 and record, next to the binary, the source state it was built
# from.
#
# Why this exists.  On 2026-09-04 build_Intel_8592/gem5.opt was replaced in
# place.  The binary it replaced had produced every published magnitude in the
# h1bw campaigns, and at that moment its source state was captured by no
# commit -- so the campaign records cited a gem5_sha256 for a file that no
# longer existed and could not be rebuilt.  A run manifest cannot repair this
# after the fact: it records the tree as it stands at LAUNCH, which for the
# bwt16/bwt31 cells was three days newer than the binary they ran.  The build
# is the only point where the source and the binary provably coexist.
# See experiments/asplos/BUILD_PROVENANCE.md.
#
#   build_gem5.sh [variant] [scons args ...]     default variant: Intel_8592
#
# Writes build_<variant>/BUILD_PROVENANCE.json, and BUILD_SOURCE.diff when the
# tree is dirty.  A dirty tree is NOT refused -- in this project that would
# refuse every build -- but it is recorded as an identity rather than as a
# boolean, so "which dirty tree" is answerable later.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VARIANT=${1:-Intel_8592}
[ $# -gt 0 ] && shift
BUILD_DIR="$ROOT/build_$VARIANT"
TARGET="$BUILD_DIR/gem5.opt"
PROV="$BUILD_DIR/BUILD_PROVENANCE.json"
DIFF="$BUILD_DIR/BUILD_SOURCE.diff"

# HEAD + the full working diff + every untracked file's contents, hashed to one
# value.  Lifted from source_identity() in fs_boot_checkpoint.sh so that a
# checkpoint manifest and a build manifest name a tree the same way.
source_fingerprint()
{
    {
        printf 'HEAD %s\n' "$(git -C "$ROOT" rev-parse HEAD)"
        git -C "$ROOT" diff --binary HEAD --
        git -C "$ROOT" ls-files --others --exclude-standard -z |
            while IFS= read -r -d '' file; do
                printf 'UNTRACKED %s ' "$file"
                sha256sum "$ROOT/$file" | awk '{print $1}'
            done
    } | sha256sum | awk '{print $1}'
}

git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || {
    echo "FAIL not a git tree: $ROOT" >&2; exit 2; }

SOURCE_HEAD=$(git -C "$ROOT" rev-parse HEAD)
SOURCE_DESCRIBE=$(git -C "$ROOT" describe --tags --long --dirty --always)
SOURCE_FINGERPRINT=$(source_fingerprint)
if [ -n "$(git -C "$ROOT" status --porcelain=v1 --untracked-files=all)" ]; then
    SOURCE_DIRTY=true
else
    SOURCE_DIRTY=false
fi

# Refuse to leave a stale manifest describing the previous binary while the new
# one is being linked: a reader between those two events would be misled.
rm -f "$PROV"

echo "build_gem5.sh: $VARIANT from $SOURCE_DESCRIBE (dirty=$SOURCE_DIRTY)"
"${SCONS:-scons}" "build_$VARIANT/gem5.opt" "$@"

[ -x "$TARGET" ] || { echo "FAIL build produced no $TARGET" >&2; exit 2; }

# The diff is the only way back to a dirty tree, so it is written before the
# manifest that claims it exists, and its absence is fatal rather than warned.
if [ "$SOURCE_DIRTY" = true ]; then
    git -C "$ROOT" diff --binary HEAD -- > "$DIFF" || {
        echo "FAIL could not record working diff to $DIFF" >&2; exit 2; }
    git -C "$ROOT" ls-files --others --exclude-standard \
        > "$BUILD_DIR/BUILD_UNTRACKED.txt"
else
    rm -f "$DIFF" "$BUILD_DIR/BUILD_UNTRACKED.txt"
fi

tmp="$PROV.$$"
cat > "$tmp" <<EOF
{
  "format": "gem5-build-provenance-v1",
  "variant": "$VARIANT",
  "gem5_sha256": "$(sha256sum "$TARGET" | awk '{print $1}')",
  "gem5_bytes": $(stat -c %s "$TARGET"),
  "gem5_git_describe": "$SOURCE_DESCRIBE",
  "gem5_git_head": "$SOURCE_HEAD",
  "gem5_source_dirty": $SOURCE_DIRTY,
  "gem5_source_fingerprint": "$SOURCE_FINGERPRINT",
  "gem5_source_diff": $([ "$SOURCE_DIRTY" = true ] && echo "\"BUILD_SOURCE.diff\"" || echo null),
  "built": "$(date -Is)",
  "host": "$(hostname)",
  "note": "gem5 embeds its compile timestamp and build-dir paths, so a rebuild from gem5_git_head will not reproduce gem5_sha256; only behaviour is reproducible"
}
EOF
mv "$tmp" "$PROV"
echo "build_gem5.sh: recorded $PROV"
