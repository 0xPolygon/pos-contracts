#!/bin/bash

create_interface () {
    contract="$(basename "$file" | cut -d. -f1)"
    dir="$(dirname "$file")"
    cast interface "$file" -n $contract > tools/interfaces/$contract.generated.sol
}

forge compile --skip test script

mkdir -p tools/interfaces

find out -type f -not -path "*.generated*" -print0 | while read -d $'\0' file
do
  echo $file
  create_interface 
done 


