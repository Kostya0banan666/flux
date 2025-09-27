#!/usr/bin/env bash


FILES_PATTERN='(.yml|.yaml)$'
CRYPT_TAG='^ENC\[AES256_GCM,data'

for f in $(find ${1:-.} -type f -not -path "./.git/*" | grep -E $FILES_PATTERN)
do
  if [ -f $f ]; then
    LENGTH=$(cat $f | yq '.|length'  | grep -v -- '---' | wc -l)
    for i in $(seq 0 $(($LENGTH-1)))
    do
      if [ $(cat $f | yq "select(di == $i) | .kind" 2> /dev/null || echo "oops" ) == "Secret" ]; then
        for i in $(cat $f | yq -r "select(di == $i) | (.stringData, .data) | to_entries | .[].value")
        do
          MATCH=$(echo $i | grep --no-messages -- "$CRYPT_TAG")
          if [ -z $MATCH ] ; then
              echo "Encrypting $f"
              sops -e -i $f
          fi
        done
      fi
    done
  fi
done
