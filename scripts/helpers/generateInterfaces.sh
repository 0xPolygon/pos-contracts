#!/bin/bash

create_interface () {
    contract="$(basename "$file" | cut -d. -f1)"
    dir="$(dirname "$file")"
    cast interface "$file" -n $contract > ./interfaces/$contract.generated.sol
}

#forge build

mkdir -p interfaces

find ../../out -type f -print0 | while read -d $'\0' file
do
  echo $file
  create_interface 
done 


