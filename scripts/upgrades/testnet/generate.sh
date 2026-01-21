#!/bin/sh

# todo: figure out what contracts did have changed.

output_file="2026_01_20_contracts.txt"

npx hardhat --network testnet getUpgradeCalldata --no-storage-check --output "$output_file" --contract StakingHbbft --init-func initializeV3
