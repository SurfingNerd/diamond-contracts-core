#!/bin/sh

# todo: figure out what contracts did have changed.

output_file="2025_11_09_contracts.txt"

npx hardhat --network testnet getUpgradeCalldata --no-storage-check --output "$output_file" --contract StakingHbbft --init-func initializeV2
