// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;



/// @dev Implements staking and withdrawal logic.
contract StakingHbbft is StakingHbbftBase {
    // ================================================ Events ========================================================

    /// @dev Emitted by the `claimOrderedWithdraw` function to signal the staker withdrew the specified
    /// amount of requested coins from the specified pool during the specified staking epoch.
    /// @param fromPoolStakingAddress The pool from which the `staker` withdrew the `amount`.
    /// @param staker The address of the staker that withdrew the `amount`.
    /// @param stakingEpoch The serial number of the staking epoch during which the claim was made.
    /// @param nativeCoinsAmount The withdrawal amount.
    event ClaimedOrderedWithdrawal(
        address indexed fromPoolStakingAddress,
        address indexed staker,
        uint256 indexed stakingEpoch,
        uint256 amount
    );

    // =============================================== Setters ========================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Prevents initialization of implementation contract
        _disableInitializers();
    }

    /// @dev Fallback function. Prevents direct sending native coins to this contract.
    receive() external payable {
        revert("Not payable");
    }

    /// @dev Initializes the network parameters.
    /// Can only be called by the constructor of the `InitializerHbbft` contract or owner.
    /// @param _contractOwner The address of the contract owner
    /// @param stakingParams stores other parameters due to stack too deep issue
    ///  _validatorSetContract The address of the `ValidatorSetHbbft` contract.
    ///  _initialStakingAddresses The array of initial validators' staking addresses.
    ///  _delegatorMinStake The minimum allowed amount of delegator stake in Wei.
    ///  _candidateMinStake The minimum allowed amount of candidate/validator stake in Wei.
    ///  _stakingFixedEpochDuration The fixed duration of each epoch before keyGen starts.
    ///  _stakingTransitionTimeframeLength Length of the timeframe in seconds for the transition
    /// to the new validator set.
    ///  _stakingWithdrawDisallowPeriod The duration period at the end of a staking epoch
    /// during which participants cannot stake/withdraw/order/claim their staking coins
    function initialize(
        address _contractOwner,
        StakingParams calldata stakingParams,
        bytes32[] calldata _publicKeys,
        bytes16[] calldata _internetAddresses
    ) external initializer {
        require(_contractOwner != address(0), "Owner address cannot be 0");

        require(stakingParams._stakingFixedEpochDuration != 0, "FixedEpochDuration is 0");
        require(
            stakingParams._stakingFixedEpochDuration > stakingParams._stakingWithdrawDisallowPeriod,
            "FixedEpochDuration must be longer than withdrawDisallowPeriod"
        );
        require(stakingParams._stakingWithdrawDisallowPeriod != 0, "WithdrawDisallowPeriod is 0");
        require(stakingParams._stakingTransitionTimeframeLength != 0, "The transition timeframe must be longer than 0");
        require(
            stakingParams._stakingTransitionTimeframeLength < stakingParams._stakingFixedEpochDuration,
            "The transition timeframe must be shorter then the epoch duration"
        );

        __Ownable_init();
        _transferOwnership(_contractOwner);

        _initialize(
            stakingParams._validatorSetContract,
            stakingParams._initialStakingAddresses,
            stakingParams._delegatorMinStake,
            stakingParams._candidateMinStake,
            stakingParams._maxStake,
            _publicKeys,
            _internetAddresses
        );

        stakingFixedEpochDuration = stakingParams._stakingFixedEpochDuration;
        stakingWithdrawDisallowPeriod = stakingParams._stakingWithdrawDisallowPeriod;
        //note: this might be still 0 when created in the genesis block.
        stakingEpochStartTime = block.timestamp;
        stakingTransitionTimeframeLength = stakingParams._stakingTransitionTimeframeLength;
    }

    function setStakingTransitionTimeframeLength(uint256 _value) external onlyOwner {
        require(_value > 10, "The transition timeframe must be longer than 10");
        require(_value < stakingFixedEpochDuration, "The transition timeframe must be smaller than the epoch duration");

        stakingTransitionTimeframeLength = _value;
    }

    function setStakingFixedEpochDuration(uint256 _value) external onlyOwner {
        require(
            _value > stakingTransitionTimeframeLength,
            "The fixed epoch duration timeframe must be greater than the transition timeframe length"
        );
        stakingFixedEpochDuration = _value;
    }

    /// @dev Sets (updates) the limit of the minimum candidate stake (CANDIDATE_MIN_STAKE).
    /// Can only be called by the `owner`.
    /// @param _minStake The value of a new limit in Wei.
    function setCandidateMinStake(uint256 _minStake) external onlyOwner {
        candidateMinStake = _minStake;
    }

    /// @dev Sets (updates) the limit of the minimum delegator stake (DELEGATOR_MIN_STAKE).
    /// Can only be called by the `owner`.
    /// @param _minStake The value of a new limit in Wei.
    function setDelegatorMinStake(uint256 _minStake) external onlyOwner {
        delegatorMinStake = _minStake;
    }

    /// @dev Sets the timetamp of the current epoch's last block as the start time of the upcoming staking epoch.
    /// Called by the `ValidatorSetHbbft.newValidatorSet` function at the last block of a staking epoch.
    /// @param _timestamp The starting time of the very first block in the upcoming staking epoch.
    function setStakingEpochStartTime(uint256 _timestamp) external onlyValidatorSetContract {
        stakingEpochStartTime = _timestamp;
        stakingEpochStartBlock = block.number;
    }

    /// @dev set's the validators ip address.
    /// this function can only be called by the validator Set contract.
    /// @param _validatorAddress address if the validator. (mining address)
    /// @param _ip IPV4 address of a running Node Software or Proxy.
    function setValidatorInternetAddress(
        address _validatorAddress,
        bytes16 _ip,
        bytes2 _port
    ) external onlyValidatorSetContract {
        poolInfo[_validatorAddress].internetAddress = _ip;
        poolInfo[_validatorAddress].port = _port;
    }

    /// @dev Increments the serial number of the current staking epoch.
    /// Called by the `ValidatorSetHbbft.newValidatorSet` at the last block of the finished staking epoch.
    function incrementStakingEpoch() external onlyValidatorSetContract {
        stakingEpoch++;
        currentKeyGenExtraTimeWindow = 0;
    }

    /// @dev Notifies hbbft staking contract that the
    /// key generation has failed, and a new round
    /// of keygeneration starts.
    function notifyKeyGenFailed() public onlyValidatorSetContract {
        // we allow a extra time window for the current key generation
        // equal in the size of the usual transition timeframe.
        currentKeyGenExtraTimeWindow += stakingTransitionTimeframeLength;
    }

    /// @dev Notifies hbbft staking contract about a detected
    /// network offline time.
    /// if there is no handling for this,
    /// validators got chosen outside the transition timewindow
    /// and get banned immediatly, since they never got their chance
    /// to write their keys.
    /// more about: https://github.com/DMDcoin/hbbft-posdao-contracts/issues/96
    function notifyNetworkOfftimeDetected(uint256 detectedOfflineTime) public onlyValidatorSetContract {
        currentKeyGenExtraTimeWindow =
            currentKeyGenExtraTimeWindow +
            detectedOfflineTime +
            stakingTransitionTimeframeLength;
    }

    /// @dev Notifies hbbft staking contract that a validator
    /// asociated with the given `_stakingAddress` became
    /// available again and can be put on to the list
    /// of available nodes again.
    function notifyAvailability(address _stakingAddress) public onlyValidatorSetContract {
        if (stakeAmount[_stakingAddress][_stakingAddress] >= candidateMinStake) {
            _addPoolActive(_stakingAddress, true);
            _setLikelihood(_stakingAddress);
        }
    }

    /// @dev Adds a new candidate's pool to the list of active pools (see the `getPools` getter) and
    /// moves the specified amount of staking coins from the candidate's staking address
    /// to the candidate's pool. A participant calls this function using their staking address when
    /// they want to create a pool. This is a wrapper for the `stake` function.
    /// @param _miningAddress The mining address of the candidate. The mining address is bound to the staking address
    /// (msg.sender). This address cannot be equal to `msg.sender`.
    function addPool(address _miningAddress, bytes calldata _publicKey, bytes16 _ip) external payable gasPriceIsValid {
        address stakingAddress = msg.sender;
        uint256 amount = msg.value;
        validatorSetContract.setStakingAddress(_miningAddress, stakingAddress);
        // The staking address and the staker are the same.
        _stake(stakingAddress, stakingAddress, amount);
        poolInfo[stakingAddress].publicKey = _publicKey;
        poolInfo[stakingAddress].internetAddress = _ip;

        emit PlacedStake(stakingAddress, stakingAddress, stakingEpoch, amount);
    }

    /// @dev Removes the candidate's or validator's pool from the `pools` array (a list of active pools which
    /// can be retrieved by the `getPools` getter). When a candidate or validator wants to remove their pool,
    /// they should call this function from their staking address.
    function removeMyPool() external gasPriceIsValid {
        address stakingAddress = msg.sender;
        address miningAddress = validatorSetContract.miningByStakingAddress(stakingAddress);
        // initial validator cannot remove their pool during the initial staking epoch
        require(
            stakingEpoch > 0 || !validatorSetContract.isValidator(miningAddress),
            "Can't remove pool during 1st staking epoch"
        );
        _removePool(stakingAddress);
    }

    /// @dev set's the pool info for a specific ethereum address.
    /// @param _publicKey public key of the (future) signing address.
    /// @param _ip (optional) IPV4 address of a running Node Software or Proxy.
    /// @param _port (optional) port of IPv4 address of a running Node Software or Proxy.
    /// Stores the supplied data for a staking (pool) address.
    /// This function is external available without security checks,
    /// since no array operations are used in the implementation,
    /// this allows the flexibility to set the pool information before
    /// adding the stake to the pool.
    function setPoolInfo(bytes calldata _publicKey, bytes16 _ip, bytes2 _port) external {
        poolInfo[msg.sender].publicKey = _publicKey;
        poolInfo[msg.sender].internetAddress = _ip;
        poolInfo[msg.sender].port = _port;
    }

    /// @dev Removes a specified pool from the `pools` array (a list of active pools which can be retrieved by the
    /// `getPools` getter). Called by the `ValidatorSetHbbft._removeMaliciousValidator` internal function,
    /// and the `ValidatorSetHbbft.handleFailedKeyGeneration` function
    /// when a pool must be removed by the algorithm.
    /// @param _stakingAddress The staking address of the pool to be removed.
    function removePool(address _stakingAddress) external onlyValidatorSetContract {
        _removePool(_stakingAddress);
    }

    /// @dev Removes pools which are in the `_poolsToBeRemoved` internal array from the `pools` array.
    /// Called by the `ValidatorSetHbbft.newValidatorSet` function when a pool must be removed by the algorithm.
    function removePools() external onlyValidatorSetContract {
        address[] memory poolsToRemove = _poolsToBeRemoved.values();
        for (uint256 i = 0; i < poolsToRemove.length; i++) {
            _removePool(poolsToRemove[i]);
        }

        _setLikelihood(_poolStakingAddress);

        emit OrderedWithdrawal(_poolStakingAddress, staker, stakingEpoch, _amount);
    }

    /// @dev Withdraws the staking coins from the specified pool ordered during the previous staking epochs with
    /// the `orderWithdraw` function. The ordered amount can be retrieved by the `orderedWithdrawAmount` getter.
    /// @param _poolStakingAddress The staking address of the pool from which the ordered coins are withdrawn.
    function claimOrderedWithdraw(address _poolStakingAddress) external gasPriceIsValid {
        address payable staker = payable(msg.sender);

        require(
            stakingEpoch > orderWithdrawEpoch[_poolStakingAddress][staker],
            "cannot claim ordered withdraw in the same epoch it was ordered."
        );
        require(
            _isWithdrawAllowed(
                validatorSetContract.miningByStakingAddress(_poolStakingAddress),
                staker != _poolStakingAddress
            ),
            "ClaimOrderedWithdraw: Withdraw not allowed"
        );

        uint256 claimAmount = orderedWithdrawAmount[_poolStakingAddress][staker];
        require(claimAmount != 0, "claim amount must not be 0");

        orderedWithdrawAmount[_poolStakingAddress][staker] = 0;
        orderedWithdrawAmountTotal[_poolStakingAddress] = orderedWithdrawAmountTotal[_poolStakingAddress] - claimAmount;

        if (stakeAmount[_poolStakingAddress][staker] == 0) {
            _withdrawCheckPool(_poolStakingAddress, staker);
        }

        TransferUtils.transferNativeEnsure(staker, claimAmount);

        emit ClaimedOrderedWithdrawal(_poolStakingAddress, staker, stakingEpoch, claimAmount);
    }

    /// @dev Distribute abandoned stakes among Reinsert and Governance pots.
    /// 50% goes to reinsert and 50% to governance pot.
    /// Coins are considered abandoned if they were staked on a validator inactive for 10 years.
    function recoverAbandonedStakes() external gasPriceIsValid {
        uint256 totalAbandonedAmount = 0;

        address[] memory inactivePools = _poolsInactive.values();
        require(inactivePools.length != 0, "nothing to recover");

        for (uint256 i = 0; i < inactivePools.length; ++i) {
            address stakingAddress = inactivePools[i];

            if (_isPoolEmpty(stakingAddress) || !validatorSetContract.isValidatorAbandoned(stakingAddress)) {
                continue;
            }

            _poolsInactive.remove(stakingAddress);
            abandonedAndRemoved[stakingAddress] = true;

            uint256 gatheredPerStakingAddress = stakeAmountTotal[stakingAddress];
            stakeAmountTotal[stakingAddress] = 0;

            address[] memory delegators = poolDelegators(stakingAddress);
            for (uint256 j = 0; j < delegators.length; ++j) {
                address delegator = delegators[j];

                stakeAmount[stakingAddress][delegator] = 0;
                _removePoolDelegator(stakingAddress, delegator);
            }

            totalAbandonedAmount += gatheredPerStakingAddress;

            emit GatherAbandonedStakes(msg.sender, stakingAddress, gatheredPerStakingAddress);
        }

        require(totalAbandonedAmount != 0, "nothing to recover");

        uint256 governanceShare = totalAbandonedAmount / 2;
        uint256 reinsertShare = totalAbandonedAmount - governanceShare;

        IBlockRewardHbbft blockRewardHbbft = IBlockRewardHbbft(validatorSetContract.blockRewardContract());
        address governanceAddress = blockRewardHbbft.getGovernanceAddress();

        // slither-disable-next-line arbitrary-send-eth
        blockRewardHbbft.addToReinsertPot{ value: reinsertShare }();
        TransferUtils.transferNative(governanceAddress, governanceShare);

        emit RecoverAbandonedStakes(msg.sender, reinsertShare, governanceShare);
    }

    /// @dev Makes snapshots of total amount staked into the specified pool
    /// before the specified staking epoch. Used by the `reward` function.
    /// @param _epoch The number of upcoming staking epoch.
    /// @param _stakingPool The staking address of the pool.
    function snapshotPoolStakeAmounts(uint256 _epoch, address _stakingPool) external onlyBlockRewardContract {
        if (snapshotPoolTotalStakeAmount[_epoch][_stakingPool] != 0) {
            return;
        }

        uint256 totalAmount = stakeAmountTotal[_stakingPool];
        if (totalAmount == 0) {
            return;
        }

        snapshotPoolTotalStakeAmount[_epoch][_stakingPool] = totalAmount;
        snapshotPoolValidatorStakeAmount[_epoch][_stakingPool] = stakeAmount[_stakingPool][_stakingPool];
    }

    // =============================================== Getters ========================================================

    /// @dev Returns reward amount in native coins for the specified pool, the specified staking epochs,
    /// and the specified staker address (delegator or validator).
    /// @param _stakingEpochs The list of staking epochs in ascending order.
    /// If the list is empty, it is taken with `BlockRewardHbbft.epochsPoolGotRewardFor` getter.
    /// @param _poolStakingAddress The staking address of the pool for which the amounts need to be returned.
    /// @param _staker The staker address (validator's staking address or delegator's address).
    function getRewardAmount(
        uint256[] memory _stakingEpochs,
        address _poolStakingAddress,
        uint256 _validatorMinRewardPercent
    ) external payable onlyBlockRewardContract {
        // msg.value is a pool reward
        if (msg.value == 0) {
            return;
        }

        uint256 poolReward = msg.value;
        uint256 totalStake = snapshotPoolTotalStakeAmount[stakingEpoch][_poolStakingAddress];
        uint256 validatorStake = snapshotPoolValidatorStakeAmount[stakingEpoch][_poolStakingAddress];

        uint256 validatorReward = 0;

        if (totalStake > validatorStake) {
            address[] memory delegators = poolDelegators(_poolStakingAddress);

            uint256 delegatorsStake = totalStake - validatorStake;

            bool minRewardPercentExceeded = validatorStake * (100 - _validatorMinRewardPercent) >
                delegatorsStake * _validatorMinRewardPercent;

            validatorReward = _validatorRewardShare(
                minRewardPercentExceeded,
                validatorStake,
                totalStake,
                poolReward,
                _validatorMinRewardPercent
            );

            for (uint256 i = 0; i < delegators.length; ++i) {
                uint256 delegatorReward = _delegatorRewardShare(
                    minRewardPercentExceeded,
                    totalStake,
                    _getDelegatorStake(stakingEpoch, _poolStakingAddress, delegators[i]),
                    delegatorsStake,
                    poolReward,
                    _validatorMinRewardPercent
                );

                stakeAmount[_poolStakingAddress][delegators[i]] += delegatorReward;
                _stakeAmountByEpoch[_poolStakingAddress][delegators[i]][stakingEpoch] += delegatorReward;
            }
        } else {
            // Whole pool stake belongs to the pool owner
            // and he received all the rewards.
            validatorReward = poolReward;
        }

        stakeAmount[_poolStakingAddress][_poolStakingAddress] += validatorReward;
        stakeAmountTotal[_poolStakingAddress] += poolReward;

        _setLikelihood(_poolStakingAddress);

        emit RestakeReward(_poolStakingAddress, stakingEpoch, validatorReward, poolReward - validatorReward);
    }

    /// @dev Orders coins withdrawal from the staking address of the specified pool to the
    /// staker's address. The requested coins can be claimed after the current staking epoch is complete using
    /// the `claimOrderedWithdraw` function.
    /// @param _poolStakingAddress The staking address of the pool from which the amount will be withdrawn.
    /// @param _amount The amount to be withdrawn. A positive value means the staker wants to either set or
    /// increase their withdrawal amount. A negative value means the staker wants to decrease a
    /// withdrawal amount that was previously set. The amount cannot exceed the value returned by the
    /// `maxWithdrawOrderAllowed` getter.
    function orderWithdraw(address _poolStakingAddress, int256 _amount) external gasPriceIsValid {
        require(_poolStakingAddress != address(0), "poolStakingAddress must not be 0x0");
        require(_amount != 0, "ordered withdraw amount must not be 0");

        address staker = msg.sender;

        require(
            _isWithdrawAllowed(
                validatorSetContract.miningByStakingAddress(_poolStakingAddress),
                staker != _poolStakingAddress
            ),
            "OrderWithdraw: not allowed"
        );

        uint256 newOrderedAmount = orderedWithdrawAmount[_poolStakingAddress][staker];
        uint256 newOrderedAmountTotal = orderedWithdrawAmountTotal[_poolStakingAddress];
        uint256 newStakeAmount = stakeAmount[_poolStakingAddress][staker];
        uint256 newStakeAmountTotal = stakeAmountTotal[_poolStakingAddress];
        if (_amount > 0) {
            uint256 amount = uint256(_amount);

            // How much can `staker` order for withdrawal from `_poolStakingAddress` at the moment?
            require(
                amount <= maxWithdrawOrderAllowed(_poolStakingAddress, staker),
                "OrderWithdraw: maxWithdrawOrderAllowed exceeded"
            );

            newOrderedAmount = newOrderedAmount + amount;
            newOrderedAmountTotal = newOrderedAmountTotal + amount;
            newStakeAmount = newStakeAmount - amount;
            newStakeAmountTotal = newStakeAmountTotal - amount;
            orderWithdrawEpoch[_poolStakingAddress][staker] = stakingEpoch;
        } else {
            uint256 amount = uint256(-_amount);
            newOrderedAmount = newOrderedAmount - amount;
            newOrderedAmountTotal = newOrderedAmountTotal - amount;
            newStakeAmount = newStakeAmount + amount;
            newStakeAmountTotal = newStakeAmountTotal + amount;
        }
        orderedWithdrawAmount[_poolStakingAddress][staker] = newOrderedAmount;
        orderedWithdrawAmountTotal[_poolStakingAddress] = newOrderedAmountTotal;
        stakeAmount[_poolStakingAddress][staker] = newStakeAmount;
        stakeAmountTotal[_poolStakingAddress] = newStakeAmountTotal;

        if (staker == _poolStakingAddress) {
            // The amount to be withdrawn must be the whole staked amount or
            // must not exceed the diff between the entire amount and `candidateMinStake`
            require(
                newStakeAmount == 0 || newStakeAmount >= candidateMinStake,
                "newStake Amount must be greater than the min stake."
            );

            if (_amount > 0) {
                // if the validator orders the `_amount` for withdrawal
                if (newStakeAmount == 0) {
                    // If the validator orders their entire stake,
                    // mark their pool as `to be removed`
                    _addPoolToBeRemoved(_poolStakingAddress);
                }
            } else {
                // If the validator wants to reduce withdrawal value,
                // add their pool as `active` if it hasn't been already done.
                _addPoolActive(_poolStakingAddress, true);
            }
        } else {
            // The amount to be withdrawn must be the whole staked amount or
            // must not exceed the diff between the entire amount and `delegatorMinStake`
            require(
                newStakeAmount == 0 || newStakeAmount >= delegatorMinStake,
                "newStake Amount must be greater than the min stake."
            );

            if (_amount > 0) {
                // if the delegator orders the `_amount` for withdrawal
                if (newStakeAmount == 0) {
                    // If the delegator orders their entire stake,
                    // remove the delegator from delegator list of the pool
                    _removePoolDelegator(_poolStakingAddress, staker);
                }
            } else {
                // If the delegator wants to reduce withdrawal value,
                // add them to delegator list of the pool if it hasn't already done
                _addPoolDelegator(_poolStakingAddress, staker);
            }

            // Remember stake movement to use it later in the `claimReward` function
            // _snapshotDelegatorStake(_poolStakingAddress, staker);
        }

        _setLikelihood(_poolStakingAddress);

        emit OrderedWithdrawal(_poolStakingAddress, staker, stakingEpoch, _amount);
    }

    /// @dev Withdraws the staking coins from the specified pool ordered during the previous staking epochs with
    /// the `orderWithdraw` function. The ordered amount can be retrieved by the `orderedWithdrawAmount` getter.
    /// @param _poolStakingAddress The staking address of the pool from which the ordered coins are withdrawn.
    function claimOrderedWithdraw(address _poolStakingAddress) external gasPriceIsValid {
        address payable staker = payable(msg.sender);

        require(
            stakingEpoch > orderWithdrawEpoch[_poolStakingAddress][staker],
            "cannot claim ordered withdraw in the same epoch it was ordered."
        );
        require(
            _isWithdrawAllowed(
                validatorSetContract.miningByStakingAddress(_poolStakingAddress),
                staker != _poolStakingAddress
            ),
            "ClaimOrderedWithdraw: Withdraw not allowed"
        );

        uint256 claimAmount = orderedWithdrawAmount[_poolStakingAddress][staker];
        require(claimAmount != 0, "claim amount must not be 0");

        orderedWithdrawAmount[_poolStakingAddress][staker] = 0;
        orderedWithdrawAmountTotal[_poolStakingAddress] = orderedWithdrawAmountTotal[_poolStakingAddress] - claimAmount;

        if (stakeAmount[_poolStakingAddress][staker] == 0) {
            _withdrawCheckPool(_poolStakingAddress, staker);
        }

        TransferUtils.transferNativeEnsure(staker, claimAmount);

        emit ClaimedOrderedWithdrawal(_poolStakingAddress, staker, stakingEpoch, claimAmount);
    }

    /// @dev Distribute abandoned stakes among Reinsert and Governance pots.
    /// 50% goes to reinsert and 50% to governance pot.
    /// Coins are considered abandoned if they were staked on a validator inactive for 10 years.
    function recoverAbandonedStakes() external gasPriceIsValid {
        uint256 totalAbandonedAmount = 0;

        address[] memory inactivePools = _poolsInactive.values();
        require(inactivePools.length != 0, "nothing to recover");

        for (uint256 i = 0; i < inactivePools.length; ++i) {
            address stakingAddress = inactivePools[i];

            if (_isPoolEmpty(stakingAddress) || !validatorSetContract.isValidatorAbandoned(stakingAddress)) {
                continue;
            }

            _poolsInactive.remove(stakingAddress);
            abandonedAndRemoved[stakingAddress] = true;

            uint256 gatheredPerStakingAddress = stakeAmountTotal[stakingAddress];
            stakeAmountTotal[stakingAddress] = 0;

            address[] memory delegators = poolDelegators(stakingAddress);
            for (uint256 j = 0; j < delegators.length; ++j) {
                address delegator = delegators[j];

                stakeAmount[stakingAddress][delegator] = 0;
                _removePoolDelegator(stakingAddress, delegator);
            }

            totalAbandonedAmount += gatheredPerStakingAddress;

            emit GatherAbandonedStakes(msg.sender, stakingAddress, gatheredPerStakingAddress);
        }

        require(totalAbandonedAmount != 0, "nothing to recover");

        uint256 governanceShare = totalAbandonedAmount / 2;
        uint256 reinsertShare = totalAbandonedAmount - governanceShare;

        IBlockRewardHbbft blockRewardHbbft = IBlockRewardHbbft(validatorSetContract.blockRewardContract());
        address governanceAddress = blockRewardHbbft.getGovernanceAddress();

        // slither-disable-next-line arbitrary-send-eth
        blockRewardHbbft.addToReinsertPot{ value: reinsertShare }();
        TransferUtils.transferNative(governanceAddress, governanceShare);

        emit RecoverAbandonedStakes(msg.sender, reinsertShare, governanceShare);
    }

    /// @dev Makes snapshots of total amount staked into the specified pool
    /// before the specified staking epoch. Used by the `reward` function.
    /// @param _epoch The number of upcoming staking epoch.
    /// @param _stakingPool The staking address of the pool.
    function snapshotPoolStakeAmounts(uint256 _epoch, address _stakingPool) external onlyBlockRewardContract {
        if (snapshotPoolTotalStakeAmount[_epoch][_stakingPool] != 0) {
            return;
        }

        uint256 totalAmount = stakeAmountTotal[_stakingPool];
        if (totalAmount == 0) {
            return;
        }

        snapshotPoolTotalStakeAmount[_epoch][_stakingPool] = totalAmount;
        snapshotPoolValidatorStakeAmount[_epoch][_stakingPool] = stakeAmount[_stakingPool][_stakingPool];
    }

    /**
     * @dev Sets the minimum stake required for delegators.
     * @param _minStake The new minimum stake amount.
     * Requirements:
     * - Only the contract owner can call this function.
     * - The stake amount must be within the allowed range.
     */
    function setDelegatorMinStake(uint256 _minStake)
        override
        external
        onlyOwner
        withinAllowedRange(_minStake)
    {
        delegatorMinStake = _minStake;
        emit SetDelegatorMinStake(_minStake);
    }

    /**
     * @dev Sets the allowed changeable parameter for a specific setter function.
     * @param setter The name of the setter function.
     * @param getter The name of the getter function.
     * @param params The array of allowed parameter values.
     * Requirements:
     * - Only the contract owner can call this function.
     */
    function setAllowedChangeableParameter(
        string memory setter,
        string memory getter,
        uint256[] memory params
    ) public override onlyOwner {
        super.setAllowedChangeableParameter(setter, getter, params);
    }

    /**
     * @dev Removes the allowed changeable parameter for a given function selector.
     * @param funcSelector The function selector for which the allowed changeable parameter should be removed.
     * Requirements:
     * - Only the contract owner can call this function.
     */
    function removeAllowedChangeableParameter(string memory funcSelector) public override onlyOwner {
        super.removeAllowedChangeableParameter(funcSelector);
    }

    // =============================================== Getters ========================================================

    /// @dev Returns an array of the current active pools (the staking addresses of candidates and validators).
    /// The size of the array cannot exceed MAX_CANDIDATES. A pool can be added to this array with the `_addPoolActive`
    /// internal function which is called by the `stake` or `orderWithdraw` function. A pool is considered active
    /// if its address has at least the minimum stake and this stake is not ordered to be withdrawn.
    function getPools() external view returns (address[] memory) {
        return _pools.values();
    }

    /// @dev Return the Public Key used by a Node to send targeted HBBFT Consensus Messages.
    /// @param _poolAddress The Pool Address to query the public key for.
    /// @return the public key for the given pool address.
    /// Note that the public key does not convert to the ethereum address of the pool address.
    /// The pool address is used for stacking, and not for signing HBBFT messages.
    function getPoolPublicKey(address _poolAddress) external view returns (bytes memory) {
        return poolInfo[_poolAddress].publicKey;
    }

    /// @dev Returns the registered IPv4 Address for the node.
    /// @param _poolAddress The Pool Address to query the IPv4Address for.
    /// @return IPv4 Address for the given pool address.
    function getPoolInternetAddress(address _poolAddress) external view returns (bytes16, bytes2) {
        return (poolInfo[_poolAddress].internetAddress, poolInfo[_poolAddress].port);
    }

    /// @dev Returns an array of the current inactive pools (the staking addresses of former candidates).
    /// A pool can be added to this array with the `_addPoolInactive` internal function which is called
    /// by `_removePool`. A pool is considered inactive if it is banned for some reason, if its address
    /// has zero stake, or if its entire stake is ordered to be withdrawn.
    function getPoolsInactive() external view returns (address[] memory) {
        return _poolsInactive.values();
    }

    /// @dev Returns the array of stake amounts for each corresponding
    /// address in the `poolsToBeElected` array (see the `getPoolsToBeElected` getter) and a sum of these amounts.
    /// Used by the `ValidatorSetHbbft.newValidatorSet` function when randomly selecting new validators at the last
    /// block of a staking epoch. An array value is updated every time any staked amount is changed in this pool
    /// (see the `_setLikelihood` internal function).
    /// @return likelihoods `uint256[] likelihoods` - The array of the coefficients. The array length is always equal
    /// to the length of the `poolsToBeElected` array.
    /// `uint256 sum` - The total sum of the amounts.
    function getPoolsLikelihood() external view returns (uint256[] memory likelihoods, uint256 sum) {
        return (_poolsLikelihood, _poolsLikelihoodSum);
    }

    /// @dev Returns the list of pools (their staking addresses) which will participate in a new validator set
    /// selection process in the `ValidatorSetHbbft.newValidatorSet` function. This is an array of pools
    /// which will be considered as candidates when forming a new validator set (at the last block of a staking epoch).
    /// This array is kept updated by the `_addPoolToBeElected` and `_deletePoolToBeElected` internal functions.
    function getPoolsToBeElected() external view returns (address[] memory) {
        return _poolsToBeElected;
    }

    /// @dev Returns the list of pools (their staking addresses) which will be removed by the
    /// `ValidatorSetHbbft.newValidatorSet` function from the active `pools` array (at the last block
    /// of a staking epoch). This array is kept updated by the `_addPoolToBeRemoved`
    /// and `_deletePoolToBeRemoved` internal functions. A pool is added to this array when the pool's
    /// address withdraws (or orders) all of its own staking coins from the pool, inactivating the pool.
    function getPoolsToBeRemoved() external view returns (address[] memory) {
        return _poolsToBeRemoved.values();
    }

    function getPoolValidatorStakeAmount(uint256 _epoch, address _stakingPool) external view returns (uint256) {
        return snapshotPoolValidatorStakeAmount[_epoch][_stakingPool];
    }

    /// @dev Determines whether staking/withdrawal operations are allowed at the moment.
    /// Used by all staking/withdrawal functions.
    function areStakeAndWithdrawAllowed() public pure returns (bool) {
        //experimental change to always allow to stake withdraw.
        //see https://github.com/DMDcoin/hbbft-posdao-contracts/issues/14 for discussion.
        return true;

        // used for testing
        // if (stakingFixedEpochDuration == 0){
        //     return true;
        // }
        // uint256 currentTimestamp = block.timestamp;
        // uint256 allowedDuration = stakingFixedEpochDuration - stakingWithdrawDisallowPeriod;
        // return currentTimestamp - stakingEpochStartTime > allowedDuration; //TODO: should be < not <=?
    }

    /// @dev Returns a flag indicating whether a specified address is in the `pools` array.
    /// See the `getPools` getter.
    /// @param _stakingAddress The staking address of the pool.
    function isPoolActive(address _stakingAddress) public view returns (bool) {
        return _pools.contains(_stakingAddress);
    }

    /// @dev Returns the maximum amount which can be withdrawn from the specified pool by the specified staker
    /// at the moment. Used by the `withdraw` and `moveStake` functions.
    /// @param _poolStakingAddress The pool staking address from which the withdrawal will be made.
    /// @param _staker The staker address that is going to withdraw.
    function maxWithdrawAllowed(address _poolStakingAddress, address _staker) public view returns (uint256) {
        address miningAddress = validatorSetContract.miningByStakingAddress(_poolStakingAddress);

        if (
            !_isWithdrawAllowed(miningAddress, _poolStakingAddress != _staker) ||
            abandonedAndRemoved[_poolStakingAddress]
        ) {
            return 0;
        }

        uint256 canWithdraw = stakeAmount[_poolStakingAddress][_staker];

        if (!validatorSetContract.isValidatorOrPending(miningAddress)) {
            // The pool is not a validator and is not going to become one,
            // so the staker can only withdraw staked amount minus already
            // ordered amount
            return canWithdraw;
        }

        // The pool is a validator (active or pending), so the staker can only
        // withdraw staked amount minus already ordered amount but
        // no more than the amount staked during the current staking epoch
        uint256 stakedDuringEpoch = stakeAmountByCurrentEpoch(_poolStakingAddress, _staker);

        if (canWithdraw > stakedDuringEpoch) {
            canWithdraw = stakedDuringEpoch;
        }

        return canWithdraw;
    }

    /// @dev Returns the maximum amount which can be ordered to be withdrawn from the specified pool by the
    /// specified staker at the moment. Used by the `orderWithdraw` function.
    /// @param _poolStakingAddress The pool staking address from which the withdrawal will be ordered.
    /// @param _staker The staker address that is going to order the withdrawal.
    function maxWithdrawOrderAllowed(address _poolStakingAddress, address _staker) public view returns (uint256) {
        address miningAddress = validatorSetContract.miningByStakingAddress(_poolStakingAddress);

        if (!_isWithdrawAllowed(miningAddress, _poolStakingAddress != _staker)) {
            return 0;
        }

        if (!validatorSetContract.isValidatorOrPending(miningAddress)) {
            // If the pool is a candidate (not an active validator and not pending one),
            // no one can order withdrawal from the `_poolStakingAddress`, but
            // anyone can withdraw immediately (see the `maxWithdrawAllowed` getter)
            return 0;
        }

        // If the pool is an active or pending validator, the staker can order withdrawal
        // up to their total staking amount minus an already ordered amount
        // minus an amount staked during the current staking epoch
        return stakeAmount[_poolStakingAddress][_staker] - stakeAmountByCurrentEpoch(_poolStakingAddress, _staker);
    }

    /// @dev Returns an array of the current active delegators of the specified pool.
    /// A delegator is considered active if they have staked into the specified
    /// pool and their stake is not ordered to be withdrawn.
    /// @param _poolStakingAddress The pool staking address.
    function poolDelegators(address _poolStakingAddress) public view returns (address[] memory) {
        return _poolDelegators[_poolStakingAddress].values();
    }

    /// @dev Returns an array of the current inactive delegators of the specified pool.
    /// A delegator is considered inactive if their entire stake is ordered to be withdrawn
    /// but not yet claimed.
    /// @param _poolStakingAddress The pool staking address.
    function poolDelegatorsInactive(address _poolStakingAddress) external view returns (address[] memory) {
        return _poolDelegatorsInactive[_poolStakingAddress].values();
    }

    /// @dev Returns the amount of staking coins staked into the specified pool by the specified staker
    /// during the current staking epoch (see the `stakingEpoch` getter).
    /// Used by the `stake`, `withdraw`, and `orderWithdraw` functions.
    /// @param _poolStakingAddress The pool staking address.
    /// @param _staker The staker's address.
    function stakeAmountByCurrentEpoch(address _poolStakingAddress, address _staker) public view returns (uint256) {
        return _stakeAmountByEpoch[_poolStakingAddress][_staker][stakingEpoch];
    }

    /// @dev indicates the time when the new validatorset for the next epoch gets chosen.
    /// this is the start of a timeframe before the end of the epoch,
    /// that is long enough for the validators
    /// to create a new shared key.
    function startTimeOfNextPhaseTransition() public view returns (uint256) {
        return stakingEpochStartTime + stakingFixedEpochDuration - stakingTransitionTimeframeLength;
    }

    /// @dev Returns an indicative time of the last block of the current staking epoch before key generation starts.
    function stakingFixedEpochEndTime() public view returns (uint256) {
        uint256 startTime = stakingEpochStartTime;
        return
            startTime +
            stakingFixedEpochDuration +
            currentKeyGenExtraTimeWindow -
            (stakingFixedEpochDuration == 0 ? 0 : 1);
    }

    // ============================================== Internal ========================================================
    /// @dev Initializes the network parameters. Used by the `initialize` function.
    /// @param _validatorSetContract The address of the `ValidatorSetHbbft` contract.
    /// @param _initialStakingAddresses The array of initial validators' staking addresses.
    /// @param _delegatorMinStake The minimum allowed amount of delegator stake in Wei.
    /// @param _candidateMinStake The minimum allowed amount of candidate/validator stake in Wei.
    function _initialize(
        address _validatorSetContract,
        address[] memory _initialStakingAddresses,
        uint256 _delegatorMinStake,
        uint256 _candidateMinStake,
        uint256 _maxStake,
        bytes32[] memory _publicKeys,
        bytes16[] memory _internetAddresses
    ) internal {
        require(_validatorSetContract != address(0), "ValidatorSet can't be 0");
        require(_initialStakingAddresses.length > 0, "Must provide initial mining addresses");
        require(_initialStakingAddresses.length * 2 == _publicKeys.length, "Must provide correct number of publicKeys");
        require(
            _initialStakingAddresses.length == _internetAddresses.length,
            "Must provide correct number of IP adresses"
        );
        require(_delegatorMinStake != 0, "DelegatorMinStake is 0");
        require(_candidateMinStake != 0, "CandidateMinStake is 0");
        require(_maxStake > _candidateMinStake, "maximum stake must be greater then minimum stake.");

        validatorSetContract = IValidatorSetHbbft(_validatorSetContract);

        for (uint256 i = 0; i < _initialStakingAddresses.length; i++) {
            require(_initialStakingAddresses[i] != address(0), "InitialStakingAddresses can't be 0");
            _addPoolActive(_initialStakingAddresses[i], false);
            _addPoolToBeRemoved(_initialStakingAddresses[i]);
            poolInfo[_initialStakingAddresses[i]].publicKey = abi.encodePacked(
                _publicKeys[i * 2],
                _publicKeys[i * 2 + 1]
            );
            poolInfo[_initialStakingAddresses[i]].internetAddress = _internetAddresses[i];
        }

        delegatorMinStake = _delegatorMinStake;
        candidateMinStake = _candidateMinStake;

        maxStakeAmount = _maxStake;
    }

    /// @dev Adds the specified staking address to the array of active pools returned by
    /// the `getPools` getter. Used by the `stake`, `addPool`, and `orderWithdraw` functions.
    /// @param _stakingAddress The pool added to the array of active pools.
    /// @param _toBeElected The boolean flag which defines whether the specified address should be
    /// added simultaneously to the `poolsToBeElected` array. See the `getPoolsToBeElected` getter.
    function _addPoolActive(address _stakingAddress, bool _toBeElected) internal {
        if (!isPoolActive(_stakingAddress)) {
            _pools.add(_stakingAddress);
            require(_pools.length() <= _getMaxCandidates(), "MAX_CANDIDATES pools exceeded");
        }

        _poolsInactive.remove(_stakingAddress);

        if (_toBeElected) {
            _addPoolToBeElected(_stakingAddress);
        }
    }

    /// @dev Adds the specified staking address to the array of inactive pools returned by
    /// the `getPoolsInactive` getter. Used by the `_removePool` internal function.
    /// @param _stakingAddress The pool added to the array of inactive pools.
    function _addPoolInactive(address _stakingAddress) internal {
        // This function performs internal checks if value already exists
        _poolsInactive.add(_stakingAddress);
    }

    /// @dev Adds the specified staking address to the array of pools returned by the `getPoolsToBeElected`
    /// getter. Used by the `_addPoolActive` internal function. See the `getPoolsToBeElected` getter.
    /// @param _stakingAddress The pool added to the `poolsToBeElected` array.
    function _addPoolToBeElected(address _stakingAddress) private {
        uint256 index = poolToBeElectedIndex[_stakingAddress];
        uint256 length = _poolsToBeElected.length;
        if (index >= length || _poolsToBeElected[index] != _stakingAddress) {
            poolToBeElectedIndex[_stakingAddress] = length;
            _poolsToBeElected.push(_stakingAddress);
            _poolsLikelihood.push(0); // assumes the likelihood is set with `_setLikelihood` function hereinafter
        }
        _deletePoolToBeRemoved(_stakingAddress);
    }

    /// @dev Adds the specified staking address to the array of pools returned by the `getPoolsToBeRemoved`
    /// getter. Used by withdrawal functions. See the `getPoolsToBeRemoved` getter.
    /// @param _stakingAddress The pool added to the `poolsToBeRemoved` array.
    function _addPoolToBeRemoved(address _stakingAddress) private {
        _poolsToBeRemoved.add(_stakingAddress);

        _deletePoolToBeElected(_stakingAddress);
    }

    /// @dev Deletes the specified staking address from the array of pools returned by the
    /// `getPoolsToBeElected` getter. Used by the `_addPoolToBeRemoved` and `_removePool` internal functions.
    /// See the `getPoolsToBeElected` getter.
    /// @param _stakingAddress The pool deleted from the `poolsToBeElected` array.
    function _deletePoolToBeElected(address _stakingAddress) private {
        if (_poolsToBeElected.length != _poolsLikelihood.length) return;

        uint256 indexToDelete = poolToBeElectedIndex[_stakingAddress];
        if (_poolsToBeElected.length > indexToDelete && _poolsToBeElected[indexToDelete] == _stakingAddress) {
            if (_poolsLikelihoodSum >= _poolsLikelihood[indexToDelete]) {
                _poolsLikelihoodSum -= _poolsLikelihood[indexToDelete];
            } else {
                _poolsLikelihoodSum = 0;
            }

            uint256 lastPoolIndex = _poolsToBeElected.length - 1;
            address lastPool = _poolsToBeElected[lastPoolIndex];

            _poolsToBeElected[indexToDelete] = lastPool;
            _poolsLikelihood[indexToDelete] = _poolsLikelihood[lastPoolIndex];

            poolToBeElectedIndex[lastPool] = indexToDelete;
            poolToBeElectedIndex[_stakingAddress] = 0;

            _poolsToBeElected.pop();
            _poolsLikelihood.pop();
        }
    }

    /// @dev Deletes the specified staking address from the array of pools returned by the
    /// `getPoolsToBeRemoved` getter. Used by the `_addPoolToBeElected` and `_removePool` internal functions.
    /// See the `getPoolsToBeRemoved` getter.
    /// @param _stakingAddress The pool deleted from the `poolsToBeRemoved` array.
    function _deletePoolToBeRemoved(address _stakingAddress) private {
        _poolsToBeRemoved.remove(_stakingAddress);
    }

    /// @dev Removes the specified staking address from the array of active pools returned by
    /// the `getPools` getter. Used by the `removePool`, `removeMyPool`, and withdrawal functions.
    /// @param _stakingAddress The pool removed from the array of active pools.
    function _removePool(address _stakingAddress) private {
        // This function performs existence check internally
        _pools.remove(_stakingAddress);

        if (_isPoolEmpty(_stakingAddress)) {
            _poolsInactive.remove(_stakingAddress);
        } else {
            _addPoolInactive(_stakingAddress);
        }

        _deletePoolToBeElected(_stakingAddress);
        _deletePoolToBeRemoved(_stakingAddress);
    }

    /// @dev Returns the max number of candidates (including validators). See the MAX_CANDIDATES constant.
    /// Needed mostly for unit tests.
    function _getMaxCandidates() internal pure virtual returns (uint256) {
        return MAX_CANDIDATES;
    }

    /// @dev Adds the specified address to the array of the current active delegators of the specified pool.
    /// Used by the `stake` and `orderWithdraw` functions. See the `poolDelegators` getter.
    /// @param _poolStakingAddress The pool staking address.
    /// @param _delegator The delegator's address.
    function _addPoolDelegator(address _poolStakingAddress, address _delegator) private {
        _poolDelegators[_poolStakingAddress].add(_delegator);

        _removePoolDelegatorInactive(_poolStakingAddress, _delegator);
    }

    /// @dev Adds the specified address to the array of the current inactive delegators of the specified pool.
    /// Used by the `_removePoolDelegator` internal function.
    /// @param _poolStakingAddress The pool staking address.
    /// @param _delegator The delegator's address.
    function _addPoolDelegatorInactive(address _poolStakingAddress, address _delegator) private {
        _poolDelegatorsInactive[_poolStakingAddress].add(_delegator);
    }

    /// @dev Removes the specified address from the array of the current active delegators of the specified pool.
    /// Used by the withdrawal functions. See the `poolDelegators` getter.
    /// @param _poolStakingAddress The pool staking address.
    /// @param _delegator The delegator's address.
    function _removePoolDelegator(address _poolStakingAddress, address _delegator) private {
        _poolDelegators[_poolStakingAddress].remove(_delegator);

        if (orderedWithdrawAmount[_poolStakingAddress][_delegator] != 0) {
            _addPoolDelegatorInactive(_poolStakingAddress, _delegator);
        } else {
            _removePoolDelegatorInactive(_poolStakingAddress, _delegator);
        }
    }

    /// @dev Removes the specified address from the array of the inactive delegators of the specified pool.
    /// Used by the `_addPoolDelegator` and `_removePoolDelegator` internal functions.
    /// @param _poolStakingAddress The pool staking address.
    /// @param _delegator The delegator's address.
    function _removePoolDelegatorInactive(address _poolStakingAddress, address _delegator) private {
        _poolDelegatorsInactive[_poolStakingAddress].remove(_delegator);
    }

    /// @dev Calculates (updates) the probability of being selected as a validator for the specified pool
    /// and updates the total sum of probability coefficients. Actually, the probability is equal to the
    /// amount totally staked into the pool. See the `getPoolsLikelihood` getter.
    /// Used by the staking and withdrawal functions.
    /// @param _poolStakingAddress The address of the pool for which the probability coefficient must be updated.
    function _setLikelihood(address _poolStakingAddress) private {
        (bool isToBeElected, uint256 index) = _isPoolToBeElected(_poolStakingAddress);

        if (!isToBeElected) return;

        uint256 oldValue = _poolsLikelihood[index];
        uint256 newValue = stakeAmountTotal[_poolStakingAddress];

        _poolsLikelihood[index] = newValue;

        if (newValue >= oldValue) {
            _poolsLikelihoodSum = _poolsLikelihoodSum + (newValue - oldValue);
        } else {
            _poolsLikelihoodSum = _poolsLikelihoodSum - (oldValue - newValue);
        }
    }

    /// @dev The internal function used by the `_stake` and `moveStake` functions.
    /// See the `stake` public function for more details.
    /// @param _poolStakingAddress The staking address of the pool where the coins should be staked.
    /// @param _staker The staker's address.
    /// @param _amount The amount of coins to be staked.
    function _stake(address _poolStakingAddress, address _staker, uint256 _amount) private {
        require(_poolStakingAddress != address(0), "Stake: stakingAddress is 0");

        address poolMiningAddress = validatorSetContract.miningByStakingAddress(_poolStakingAddress);
        require(poolMiningAddress != address(0), "Pool does not exist. miningAddress for that staking address is 0");
        require(_amount != 0, "Stake: stakingAmount is 0");
        require(!validatorSetContract.isValidatorBanned(poolMiningAddress), "Stake: Mining address is banned");

        require(!abandonedAndRemoved[_poolStakingAddress], "Stake: pool abandoned");
        //require(areStakeAndWithdrawAllowed(), "Stake: disallowed period");

        bool selfStake = _staker == _poolStakingAddress;
        uint256 newStakeAmount = stakeAmount[_poolStakingAddress][_staker] + _amount;

        if (selfStake) {
            // The staked amount must be at least CANDIDATE_MIN_STAKE
            require(newStakeAmount >= candidateMinStake, "Stake: candidateStake less than candidateMinStake");
        } else {
            // The staked amount must be at least DELEGATOR_MIN_STAKE
            require(newStakeAmount >= delegatorMinStake, "Stake: delegatorStake is less than delegatorMinStake");

            // The delegator cannot stake into the pool of the candidate which hasn't self-staked.
            // Also, that candidate shouldn't want to withdraw all their funds.
            require(stakeAmount[_poolStakingAddress][_poolStakingAddress] != 0, "Stake: can't delegate in empty pool");
        }

        require(stakeAmountTotal[_poolStakingAddress] + _amount <= maxStakeAmount, "stake limit has been exceeded");

        _stakeAmountByEpoch[_poolStakingAddress][_staker][stakingEpoch] += _amount;
        stakeAmountTotal[_poolStakingAddress] += _amount;

        if (selfStake) {
            // `staker` places a stake for himself and becomes a candidate
            // Add `_poolStakingAddress` to the array of pools
            _addPoolActive(_poolStakingAddress, true);

        } else {
            // Add `_staker` to the array of pool's delegators
            _addPoolDelegator(_poolStakingAddress, _staker);

            // Save amount value staked by the delegator
            _snapshotDelegatorStake(_poolStakingAddress, poolMiningAddress, _staker);
        }

        stakeAmount[_poolStakingAddress][_staker] = newStakeAmount;

        _setLikelihood(_poolStakingAddress);
    }

    /// @dev The internal function used by the `withdraw` and `moveStake` functions.
    /// See the `withdraw` public function for more details.
    /// @param _poolStakingAddress The staking address of the pool from which the coins should be withdrawn.
    /// @param _staker The staker's address.
    /// @param _amount The amount of coins to be withdrawn.
    function _withdraw(address _poolStakingAddress, address _staker, uint256 _amount) private {
        require(_poolStakingAddress != address(0), "Withdraw pool staking address must not be null");
        require(_amount != 0, "amount to withdraw must not be 0");

        // How much can `staker` withdraw from `_poolStakingAddress` at the moment?
        require(_amount <= maxWithdrawAllowed(_poolStakingAddress, _staker), "Withdraw: maxWithdrawAllowed exceeded");

        uint256 newStakeAmount = stakeAmount[_poolStakingAddress][_staker] - _amount;

        // The amount to be withdrawn must be the whole staked amount or
        // must not exceed the diff between the entire amount and MIN_STAKE
        uint256 minAllowedStake = (_poolStakingAddress == _staker) ? candidateMinStake : delegatorMinStake;
        require(
            newStakeAmount == 0 || newStakeAmount >= minAllowedStake,
            "newStake amount must be greater equal than the min stake."
        );

        if (_staker != _poolStakingAddress) {
            address miningAddress = validatorSetContract.miningByStakingAddress(_poolStakingAddress);
            _snapshotDelegatorStake(_poolStakingAddress, miningAddress, _staker);
        }

        stakeAmount[_poolStakingAddress][_staker] = newStakeAmount;
        uint256 amountByEpoch = stakeAmountByCurrentEpoch(_poolStakingAddress, _staker);
        _stakeAmountByEpoch[_poolStakingAddress][_staker][stakingEpoch] = amountByEpoch >= _amount
            ? amountByEpoch - _amount
            : 0;
        stakeAmountTotal[_poolStakingAddress] -= _amount;

        if (newStakeAmount == 0) {
            _withdrawCheckPool(_poolStakingAddress, _staker);
        }

        _setLikelihood(_poolStakingAddress);
    }

    /// @dev The internal function used by the `_withdraw` and `claimOrderedWithdraw` functions.
    /// Contains a common logic for these functions.
    /// @param _poolStakingAddress The staking address of the pool from which the coins are withdrawn.
    /// @param _staker The staker's address.
    function _withdrawCheckPool(address _poolStakingAddress, address _staker) private {
        if (_staker == _poolStakingAddress) {
            address miningAddress = validatorSetContract.miningByStakingAddress(_poolStakingAddress);
            if (validatorSetContract.isValidator(miningAddress)) {
                _addPoolToBeRemoved(_poolStakingAddress);
            } else {
                _removePool(_poolStakingAddress);
            }
        } else {
            _removePoolDelegator(_poolStakingAddress, _staker);

            if (_isPoolEmpty(_poolStakingAddress)) {
                _poolsInactive.remove(_poolStakingAddress);
            }
        }
    }

    function _snapshotDelegatorStake(
        address _stakingAddress,
        address _miningAddress,
        address _delegator
    ) private {
        if (!validatorSetContract.isValidatorOrPending(_miningAddress) || stakingEpoch == 0) {
            return;
        }

        uint256 lastSnapshotEpochNumber = _stakeSnapshotLastEpoch[_stakingAddress][_delegator];

        if (lastSnapshotEpochNumber < stakingEpoch) {
            _delegatorStakeSnapshot[_stakingAddress][_delegator][stakingEpoch] =
                stakeAmount[_stakingAddress][_delegator];
            _stakeSnapshotLastEpoch[_stakingAddress][_delegator] = stakingEpoch;
        }
    }

    function _getDelegatorStake(
        uint256 _stakingEpoch,
        address _stakingAddress,
        address _delegator
    ) private view returns (uint256) {
        if (_stakingEpoch == 0) {
            return 0;
        }

        if (_stakeSnapshotLastEpoch[_stakingAddress][_delegator] == _stakingEpoch) {
            return _delegatorStakeSnapshot[_stakingAddress][_delegator][_stakingEpoch];
        } else {
            return stakeAmount[_stakingAddress][_delegator];
        }
    }

    /// @dev Returns a boolean flag indicating whether the specified pool is fully empty
    /// (all stakes are withdrawn including ordered withdrawals).
    /// @param _poolStakingAddress The staking address of the pool
    function _isPoolEmpty(address _poolStakingAddress) private view returns (bool) {
        return stakeAmountTotal[_poolStakingAddress] == 0 && orderedWithdrawAmountTotal[_poolStakingAddress] == 0;
    }

    /// @dev Determines if the specified pool is in the `poolsToBeElected` array. See the `getPoolsToBeElected` getter.
    /// Used by the `_setLikelihood` internal function.
    /// @param _stakingAddress The staking address of the pool.
    /// @return toBeElected `bool toBeElected` - The boolean flag indicating whether the `_stakingAddress` is in the
    /// `poolsToBeElected` array.
    /// `uint256 index` - The position of the item in the `poolsToBeElected` array if `toBeElected` is `true`.
    function _isPoolToBeElected(address _stakingAddress) private view returns (bool toBeElected, uint256 index) {
        index = poolToBeElectedIndex[_stakingAddress];
        if (_poolsToBeElected.length > index && _poolsToBeElected[index] == _stakingAddress) {
            return (true, index);
        }
        return (false, 0);
    }

    /// @dev Returns `true` if withdrawal from the pool of the specified candidate/validator is allowed at the moment.
    /// Used by all withdrawal functions.
    /// @param _miningAddress The mining address of the validator's pool.
    /// @param _isDelegator Whether the withdrawal is requested by a delegator, not by a candidate/validator.
    function _isWithdrawAllowed(address _miningAddress, bool _isDelegator) private view returns (bool) {
        if (_isDelegator) {
            if (validatorSetContract.areDelegatorsBanned(_miningAddress)) {
                // The delegator cannot withdraw from the banned validator pool until the ban is expired
                return false;
            }
        } else {
            if (validatorSetContract.isValidatorBanned(_miningAddress)) {
                // The banned validator cannot withdraw from their pool until the ban is expired
                return false;
            }
        }

        return areStakeAndWithdrawAllowed();
    }

    function _delegatorRewardShare(
        bool _minRewardPercentExceeded,
        uint256 _totalStake,
        uint256 _delegatorStake,
        uint256 _allDelegatorsStaked,
        uint256 _poolReward,
        uint256 _validatorMinRewardPercent
    ) private pure returns (uint256) {
        if (_delegatorStake == 0 || _allDelegatorsStaked == 0 || _totalStake == 0) {
            return 0;
        }

        unchecked {
            uint256 share = 0;

            if (_minRewardPercentExceeded) {
                // Validator has more than validatorMinPercent %
                share = (_poolReward * _delegatorStake) / _totalStake;
            } else {
                // Validator has validatorMinPercent %
                share =
                    (_poolReward * _delegatorStake * (100 - _validatorMinRewardPercent)) /
                    (_allDelegatorsStaked * 100);
            }

            return share;
        }
    }

    function _validatorRewardShare(
        bool _minRewardPercentExceeded,
        uint256 _validatorStaked,
        uint256 _totalStaked,
        uint256 _poolReward,
        uint256 _validatorMinRewardPercent
    ) private pure returns (uint256) {
        if (_validatorStaked == 0 || _totalStaked == 0) {
            return 0;
        }

        unchecked {
            uint256 share = 0;

            if (_minRewardPercentExceeded) {
                // Validator has more than validatorMinPercent %
                share = (_poolReward * _validatorStaked) / _totalStaked;
            } else {
                // Validator has validatorMinPercent %
                share = (_poolReward * _validatorMinRewardPercent) / 100;
            }

            return share;
        }
    }
}
