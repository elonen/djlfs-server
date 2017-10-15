#!/bin/bash

set -e

if [ "x$1" == "x" ]; then
  URL_BASE='http://127.0.0.1:8000'
else
  URL_BASE="$1"
fi

curl -s "$URL_BASE" > /dev/null || { echo "ERROR: could not curl $URL_BASE. Make sure Django test server is running."; exit 1; }

function indent() { sed 's/^/    /'; }

set -e

echo "(Re)creating test dirs..."
rm -rf test_temp
mkdir test_temp
cd test_temp

if [ "x$1" == "x" ]; then
    mkdir lfs_storage_dir

	echo "Creating bare repository..."
	git init --bare bare_repo 2>&1 | indent
	cd bare_repo
	git lfs install 2>&1 | indent

	echo "Cloning empty repo..."
	cd ..
	git clone bare_repo clone1 2>&1 | indent
else
	git clone "$URL_BASE" clone1
fi

cd clone1
date > test1.txt

echo "Configuring LFS..."
if [ "x$1" == "x" ]; then
  git config -f .lfsconfig lfs.url $URL_BASE/info/lfs 2>&1 | indent
  git add .lfsconfig
fi
git lfs track '*.bin' | indent
git add .gitattributes test1.txt 2>&1 | indent

echo "Commiting config & normal files..."
git commit -m "First commit" 2>&1 | indent
echo "Pushing..."
git push 2>&1 | indent

echo "Creating some test files..."
dd if=/dev/urandom bs=1024 count=1024 of=test1.bin 2>&1 | indent
dd if=/dev/zero bs=6144 count=102400 of=test2.bin 2>&1 | indent
echo "Commiting them..."
git add *.bin | indent
git commit -m "Add some bin files" 2>&1 | indent

echo "Commiting known binary content..."
echo "testcontent" > known.bin
git add known.bin 2>&1 | indent
git commit -m "Add known bin" 2>&1 | indent

echo "Pushing..."
git push 2>&1 | indent

echo "Making another clone..."
cd ..
if [ "x$1" == "x" ]; then
	git clone bare_repo clone2 2>&1 | indent
else
	git clone "$URL_BASE" clone2
fi
cd clone2

git lfs pull 2>&1 | indent

cd ..
cmp clone1/test1.bin clone2/test1.bin || { echo "Pulled files differ"; exit 1; }

echo "Testing missing token..."
curl -o /dev/null -sw '%{http_code}' "$URL_BASE/info/lfs/objects/get/72abf2ca8f36943ebe2e49ca3a51d409ca5f0bfcffab6c9d25643c17c32889da" | grep -q '401' || { echo 'TEST FAIL: No auth error from missing token.'; exit 1; }

if [ "x$1" == "x" ]; then
	cmp clone2/known.bin lfs_storage_dir/86/03/8603effde36c3c39e50c1ad0b4909ee48318ab760c85a7555bd821b026856bf7 || { echo "Clone and storage differ?"; exit 1; }

	echo "Deleting file from storage..."
	rm -r lfs_storage_dir/86
	[ ! -e lfs_storage_dir/86/03/8603effde36c3c39e50c1ad0b4909ee48318ab760c85a7555bd821b026856bf7 ] || { echo 'Failed to delete file?'; exit 1; }

	echo "Pushing it again..."
	cd clone2
	git lfs push origin master --all 2>&1 | indent
	cd ..
	cmp clone2/known.bin lfs_storage_dir/86/03/8603effde36c3c39e50c1ad0b4909ee48318ab760c85a7555bd821b026856bf7 || { echo "Clone and storage differ?"; exit 1; }

	echo "Truncate file from storage..."
	echo "BAD" > lfs_storage_dir/86/03/8603effde36c3c39e50c1ad0b4909ee48318ab760c85a7555bd821b026856bf7

	echo "Pushing it again (test that server overwrites the truncated file)..."
	cd clone2
	git lfs push origin master --all 2>&1 | indent
	cd ..
	cmp clone2/known.bin lfs_storage_dir/86/03/8603effde36c3c39e50c1ad0b4909ee48318ab760c85a7555bd821b026856bf7 || { echo "Clone and storage differ?"; exit 1; }

	[ -z "$(ls lfs_storage_dir/tmp/)" ] || { echo "ERROR: temp dir not empty."; exit 1; }
fi

echo ""
echo "Tests passed."
echo ""
