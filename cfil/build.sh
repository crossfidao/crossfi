#! /bin/bash

file="cfil.sol"

args='[], crfi.address, '

contractName="CFil"

varName="cfil"

#####################

gas="8000000"

out="./out"

allfile="all_${file}"

cd $(dirname $0)

npx truffle-flattener ${file} |sed '/SPDX-License-Identifier/d' > ${allfile}

exec > deploy.js

solc --optimize  -o ${out} --abi --bin --overwrite $@ ${allfile}

echo -n "abi="
cat "${out}/${contractName}.abi"
echo ""
echo -n "bin='"
cat "${out}/${contractName}.bin"
echo "'"

cat <<EOF
var account = eth.accounts[0]

var gasPrice = eth.gasPrice

var ${varName} = eth.contract(abi).new(${args} {
 from: account,
 data: '0x' + bin,
 gas: "$gas",
}, function(e, contract) {
 if (e) {
     console.log("err creating contract", e);
 } else {
     if (!contract.address) {
         console.log("Contract transaction send: TransactionHash: " + contract.transactionHash + " waiting to be mined...");
     } else {
         console.log("Contract mined! Address: " + contract.address);
         address = contract.address
         console.log(contract);
     }
 }
});
EOF
